{ config, pkgs, ... }:

let
  mediaDir = "/zfs78/media";
  group = "media";

  host = "swift-009.seedbox.vip";
  port = 63526;
  user = "rapidseedbox101809";
  categories = [
    "sonarr"
    "radarr"
  ];

  # qBittorrent reports this path; the arrs' remote path mapping rewrites it
  # to localDownloads. SFTP is chrooted *at* this directory, so the rclone
  # remote sees it as its root and category folders sit directly beneath.
  remoteDownloads = "/mnt/007/${user}/Downloads";
  localDownloads = "${mediaDir}/torrents/seedbox";

  # rclone's SSH client may negotiate any of these; pin all three.
  knownHosts = pkgs.writeText "seedbox-known-hosts" ''
    [${host}]:${toString port} ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFu3F1tNRQJyNgU2EhTjVezyO4fSn8a37eOcVnquWInV
    [${host}]:${toString port} ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBM0dKY+FArQP0qDORbe0QiUzbPiufdToZSnHI2oWoJuRvHHfT308h8VGAnhOX/mA59yMwbgM5F8hUNwMUJpK/Sg=
    [${host}]:${toString port} ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCefg/7hNpNwGqUeCA11rO0tKayjhdfx8U/lC7KOwO2rJ0xytnTU1KfxY973HbCeNKSDxCJXnvgqMO8W1HQtZ4e6DI/SHabxC3wi9bky5mwFcFeLVvU3Ik0qCTaTgx/eXX7s8TAab0WVHG9E9Bvic4oEiHk599QqCWisJq6e5t/E0g2Qv1snGoeWDDzHLOat86Hvv0ekKQfNbUYbL5/2BI0BYOnuU3Nx9RqwArArhwWDl02SIphOXRrFF9xGNJN8Befhb/ghhEfeLxu8+4JJ1o5AOr0hKbxxNf0ytWXr3dmgr2VWHMEnoLmRhwaT6Ozinjwytqpf2z/ahcx8TNxQuNazViP3cVYbN9ll3t+D0Ki51yTAcFoszX+t9iSnYSW4NIOFUi+U8GJjAWJyHWq52/XFqblNxsv+D2rsPss/0V8O/pWtB8tB11hB4aTrB3b61IIa+m6VImucXGTbpxELmwjFn0hF6E1Ym8Jgs6hUWlrYlFXwaZPPNdniFRLW46Vnws=
  '';

  # Everything but the password lives in a normal rclone config. rclone reads
  # the password from RCLONE_CONFIG_SEEDBOX_PASS, which the unit derives from
  # the systemd credential.
  rcloneConfig = (pkgs.formats.ini { }).generate "rclone.conf" {
    seedbox = {
      type = "sftp";
      inherit host port user;
      known_hosts_file = knownHosts;
      set_modtime = false;
      # rclone probes these once and tries to write the result back into the
      # config; the store is read-only, so state them up front.
      md5sum_command = "none";
      sha1sum_command = "none";
    };
  };

  # `copy`, not `sync`: deleting a landed file at home must never delete it on
  # the seedbox while it is still seeding. `--inplace=false` writes in-flight
  # files under a temp name so the arrs never see a half-copied release;
  # `--min-age` skips anything qBittorrent touched in the last minute.
  pull = pkgs.writeShellApplication {
    name = "seedbox-pull";
    runtimeInputs = [ pkgs.rclone ];
    text = ''
      RCLONE_CONFIG_SEEDBOX_PASS=$(rclone obscure - < "$CREDENTIALS_DIRECTORY/password")
      export RCLONE_CONFIG_SEEDBOX_PASS
      for cat in ${toString categories}; do
        # qBittorrent creates a category directory on its first download.
        rclone lsd "seedbox:$cat" >/dev/null 2>&1 || continue
        rclone copy --inplace=false --min-age 1m --transfers 4 --checkers 8 \
          --multi-thread-streams 4 --multi-thread-cutoff 256M \
          "seedbox:$cat" "${localDownloads}/$cat"
      done
    '';
  };
in
{
  # A RapidSeedbox shared box, used for private-tracker torrents that need
  # long seeding. Its qBittorrent is a second download client in Sonarr and
  # Radarr (tagged `seedbox`, configured through their UIs); this module brings
  # finished files home so the usual import path applies, via a remote path
  # mapping of ${remoteDownloads} -> ${localDownloads}.
  age.secrets.seedbox-password.file = ../../secrets/seedbox-password.age;

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
        LoadCredential = "password:${config.age.secrets.seedbox-password.path}";
        ExecStart = "${pull}/bin/seedbox-pull";
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
