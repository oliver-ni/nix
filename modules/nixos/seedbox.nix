{ config, pkgs, ... }:

let
  mediaDir = "/zfs78/media";
  group = "media";

  host = "charon.whatbox.ca";
  port = 22;
  user = "oliverni";
  categories = [
    "sonarr"
    "radarr"
  ];

  # qBittorrent reports paths under remoteDownloads; the arrs' remote path
  # mapping rewrites them to localDownloads.
  remoteDownloads = "/home/${user}/files";
  localDownloads = "${mediaDir}/torrents/seedbox";

  # Fingerprints are published on the Whatbox slot page; rclone's SSH client
  # may negotiate any of these, so pin all three.
  knownHosts = pkgs.writeText "seedbox-known-hosts" ''
    ${host} ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHamrqU5kddKcyoORK1/W0iKqlawEMHn1Q0zo8fgKWxE
    ${host} ecdsa-sha2-nistp521 AAAAE2VjZHNhLXNoYTItbmlzdHA1MjEAAAAIbmlzdHA1MjEAAACFBAChH/2gOcFvhgEhsf2D9AGio6ChgvtpNl8i9/I+HoA8oed3e33wBTWDRrsfrUxHlKcVy6TnR7vASSrVe+TX37avUwB/YOdL2Y6aSKi0ZUMswiFnBzp4aCiijwV6yJ0tqKmvc78E7OiE2NaCRobvEXLCURFUTfKE4nNL3VYKfpTxURombQ==
    ${host} ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCrc6IGpfK2mBcKAadzhXXSXT8y1XpKaAD1O9nsqgNuQSemlaMqAcWDQcILimX1Ru1rVO+z2i23Zo7fQtAYNK79rLaoAdb2vWZAEICgRYxqTYakS3Batr686zuz7aOkTcQi2tS3lEtEqKrw+iR2g6PuWNtzDbO4TX2nPG9vkoFZ+5FhL5XQSaJa87gAonZiXk4sTyTFqGMHoKFO4nEOlE+pCjptMt6ZqlQN/kVirqNE2D4ONAhbqDPdt5ieB1LgMqF51Ejvoor+vwmM3O4h1UV1Yk5SsKQjisMUwhPnNH3vBfXJU1hM2WgoBxDllOkryQu1acR2uHE7Ke7UfzjLf4Gn
  '';

  # The pull user's ed25519 key; its public half is in the seedbox user's
  # authorized_keys.
  keyFile = config.age.secrets.seedbox-ssh-key.path;

  rcloneConfig = (pkgs.formats.ini { }).generate "rclone.conf" {
    seedbox = {
      type = "sftp";
      inherit host port user;
      key_file = keyFile;
      known_hosts_file = knownHosts;
      set_modtime = false;
      # rclone probes these once and tries to write the result back into the
      # config; the store is read-only, so state them up front.
      md5sum_command = "none";
      sha1sum_command = "none";
    };
  };

  # Several files at once and several streams per file keep the long-haul link
  # full. `copy`, not `sync`: deleting a landed file at home must
  # never delete it on the seedbox while it is still seeding. `--inplace=false`
  # writes in-flight files under a temp name so the arrs never see a
  # half-copied release; `--min-age` skips anything qBittorrent touched in the
  # last minute.
  pull = pkgs.writeShellApplication {
    name = "seedbox-pull";
    runtimeInputs = [ pkgs.rclone ];
    text = ''
      for cat in ${toString categories}; do
        # qBittorrent creates a category directory on its first download.
        rclone lsd "seedbox:${remoteDownloads}/$cat" >/dev/null 2>&1 || continue
        rclone copy --inplace=false --min-age 1m --transfers 8 --checkers 8 \
          --multi-thread-streams 4 --multi-thread-cutoff 64M --sftp-concurrency 128 \
          "seedbox:${remoteDownloads}/$cat" "${localDownloads}/$cat"
      done
    '';
  };
in
{
  # A Whatbox slot, used for private-tracker torrents that need long seeding.
  # Its qBittorrent is a second download client in Sonarr and Radarr (tagged
  # `seedbox`, configured through their UIs) behind the slot's basic-auth
  # proxy at https://qbittorrent.freedgiraffe.box.ca; this module brings
  # finished files home so the usual import path applies, via a remote path
  # mapping of ${remoteDownloads} -> ${localDownloads}.
  age.secrets.seedbox-ssh-key = {
    file = ../../secrets/seedbox-ssh-key.age;
    owner = "seedbox-pull";
    inherit group;
  };

  users.users.seedbox-pull = {
    isSystemUser = true;
    inherit group;
  };

  systemd = {
    tmpfiles.rules = map (d: "d ${localDownloads}${d} 2775 root ${group} -") (
      [ "" ] ++ map (c: "/${c}") categories
    );

    services.seedbox-pull = {
      description = "Pull completed seedbox downloads home";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      environment = {
        RCLONE_CONFIG = rcloneConfig;
        RCLONE_CACHE_DIR = "/var/cache/seedbox-pull";
      };
      serviceConfig = {
        Type = "oneshot";
        User = "seedbox-pull";
        Group = group;
        UMask = "0002";
        CacheDirectory = "seedbox-pull";
        ExecStart = "${pull}/bin/seedbox-pull";
        # rclone can sit in a blocked read on SIGTERM; killing it is safe
        # because in-flight files are temp-named and resume on the next run.
        TimeoutStopSec = 30;
      };
    };

    timers.seedbox-pull = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2m";
        OnUnitInactiveSec = "3m";
        RandomizedDelaySec = "30s";
      };
    };
  };
}
