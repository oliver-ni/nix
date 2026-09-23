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

  knownHosts = pkgs.writeText "seedbox-known-hosts" ''
    [${host}]:${toString port} ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICGyojORtn3jyFM8BVS5LetP9pXYpaC0ULP7QYUMcy9/
  '';

  # The pull user's ed25519 key; its public half is in the seedbox user's
  # authorized_keys.
  keyFile = config.age.secrets.seedbox-ssh-key.path;

  # `--partial-dir` keeps in-flight files out of the arrs' sight until rsync
  # renames them into place, and lets an interrupted pull resume. Nothing is
  # ever deleted at the source: the seedbox keeps seeding.
  pull = pkgs.writeShellApplication {
    name = "seedbox-pull";
    runtimeInputs = [
      pkgs.rsync
      pkgs.openssh
    ];
    text = ''
      ssh="ssh -i ${keyFile} -p ${toString port} -o UserKnownHostsFile=${knownHosts} -o StrictHostKeyChecking=yes -o BatchMode=yes"
      for cat in ${toString categories}; do
        # qBittorrent creates a category directory on its first download.
        $ssh "${user}@${host}" test -d "${remoteDownloads}/$cat" || continue
        rsync --archive --partial-dir=.rsync-partial \
          --no-perms --no-owner --no-group --chmod=D2775,F664 \
          --rsh="$ssh" "${user}@${host}:${remoteDownloads}/$cat/" "${localDownloads}/$cat/"
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
      serviceConfig = {
        Type = "oneshot";
        User = "seedbox-pull";
        Group = group;
        UMask = "0002";
        ExecStart = "${pull}/bin/seedbox-pull";
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
