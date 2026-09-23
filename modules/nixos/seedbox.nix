{ config, pkgs, ... }:

let
  group = "media";
  host = "charon.whatbox.ca";
  user = "oliverni";

  # qBittorrent reports paths under remoteDownloads; the arrs' remote path
  # mapping rewrites them to localDownloads.
  remoteDownloads = "/home/${user}/files";
  localDownloads = "/zfs78/media/torrents/seedbox";

  # Published on the Whatbox slot page.
  knownHosts = pkgs.writeText "seedbox-known-hosts" ''
    ${host} ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHamrqU5kddKcyoORK1/W0iKqlawEMHn1Q0zo8fgKWxE
  '';

  rcloneConfig = (pkgs.formats.ini { }).generate "rclone.conf" {
    seedbox = {
      type = "sftp";
      inherit host user;
      key_file = config.age.secrets.seedbox-ssh-key.path;
      known_hosts_file = knownHosts;
      host_key_algorithms = "ssh-ed25519";
      set_modtime = false;
    };
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
    tmpfiles.rules = [ "d ${localDownloads} 2775 root ${group} -" ];

    # `copy`, not `sync`: deleting a landed file at home must never delete it
    # on the seedbox while it is still seeding. `--inplace=false` writes
    # in-flight files under a temp name so the arrs never see a half-copied
    # release; `--min-age` skips anything qBittorrent touched in the last
    # minute. Only the arr categories come home; the slot's other folders stay.
    services.seedbox-pull = {
      description = "Pull completed seedbox downloads home";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      path = [ pkgs.rclone ];
      environment = {
        RCLONE_CONFIG = rcloneConfig;
        RCLONE_CACHE_DIR = "/var/cache/seedbox-pull";
      };
      script = ''
        rclone copy --inplace=false --min-age 1m --transfers 8 --multi-thread-streams 4 \
          --include '/{sonarr,radarr}/**' "seedbox:${remoteDownloads}" "${localDownloads}"
      '';
      serviceConfig = {
        Type = "oneshot";
        User = "seedbox-pull";
        Group = group;
        UMask = "0002";
        CacheDirectory = "seedbox-pull";
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
