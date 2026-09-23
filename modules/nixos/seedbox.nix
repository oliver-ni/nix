{ config, pkgs, ... }:

let
  mediaDir = "/zfs78/media";
  group = "media";

  host = "45.136.230.38";
  port = 2222;
  user = "user";
  categories = [
    "sonarr"
    "radarr"
  ];

  # qBittorrent reports paths under remoteDownloads; the arrs' remote path
  # mapping rewrites them to localDownloads.
  remoteDownloads = "/home/${user}/Downloads";
  localDownloads = "${mediaDir}/torrents/seedbox";

  # rclone's SSH client may negotiate any of these; pin all three.
  knownHosts = pkgs.writeText "seedbox-known-hosts" ''
    [${host}]:${toString port} ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICGyojORtn3jyFM8BVS5LetP9pXYpaC0ULP7QYUMcy9/
    [${host}]:${toString port} ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBG5NgfalbPvbFdIS6DaGgL9hFEasg4ZvCPMkq1LrZp7ujV1ijAQRmAwb+ke8hGdKVvzfiXatLiUXh0QvehVKaW4=
    [${host}]:${toString port} ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC0PEtCOq9ilkLPg6FrSlJ4fqToPI3o0j4jfccu8hPB5TVfxafjedWe6TZwabG9tYpBjx9/fXWW3bpZjiY2HajDftvz6hpnjTKw31Enwzc0/I+8DxKvvtie0iao8Nq8dvd45Omko3iSb3KyCbA/Wmd1SBnBdw1RaGkczLIHH8ISzPxrG1d6hL3dcyxaM/Xpqs/RMR4oldkJ5yChU54AXzpGVcbzAfe1BbMN6txEXiLVf9DZwn4gAa+6brTKdldzI7aR7TSWntCKH8FI0egbd2TDvnusjUzLfdlc6pOZeSQvDapwzvoTXjO2oOUqxUk+/ByXjN3iS/EA1H9aUkuoMRRxyg0TTInVxGGZLCNeoP3FhodM/MSA+bz6zESWy8E1xpIYQlT/zH80ZQM9xRMT8hH2mfVx1AEwvcHSLIlyvvey/spEoKaSzBnz84bazoYbbgYctQQJVfdA4sY9Im2fH2F/UGRe35PXWnKy6CJsKExATIzgQNJYs/0xfTy5UV749zs=
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

  # The box is in Amsterdam (~180 ms RTT), so a single TCP stream crawls under
  # any loss; several files at once and several streams per file recover most
  # of the bandwidth. `copy`, not `sync`: deleting a landed file at home must
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
  # A RapidSeedbox VPS, used for private-tracker torrents that need long
  # seeding. Its qBittorrent is a second download client in Sonarr and Radarr
  # (tagged `seedbox`, configured through their UIs) behind Apache basic auth
  # at https://qb-45-136-230-38.a.seedbox.vip; this module brings finished
  # files home so the usual import path applies, via a remote path mapping of
  # ${remoteDownloads} -> ${localDownloads}.
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
