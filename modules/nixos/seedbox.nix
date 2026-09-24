{ config, pkgs, ... }:

let
  group = "media";
  host = "charon.whatbox.ca";
  user = "oliverni";

  # qBittorrent reports paths under remoteDownloads; the arrs' remote path
  # mapping rewrites them to localDownloads.
  remoteDownloads = "/home/${user}/files";
  localDownloads = "/zfs78/media/torrents/seedbox";
  qbittorrent = "https://qbittorrent.freedgiraffe.box.ca";

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
      # Never run md5sum on the slot: the shared HDD is what qBittorrent is
      # writing to.
      disable_hashcheck = true;
    };
  };

  ratioGrab = pkgs.writers.writePython3Bin "seedbox-ratio-grab" {
    libraries = [ pkgs.python3Packages.requests ];
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./seedbox/ratio-grab.py);
in
{
  # A Whatbox slot, used for private-tracker torrents that need long seeding.
  # Its qBittorrent is a second download client in Sonarr and Radarr (tagged
  # `seedbox`, configured through their UIs) behind the slot's basic-auth
  # proxy at https://qbittorrent.freedgiraffe.box.ca; this module brings
  # finished files home so the usual import path applies, via a remote path
  # mapping of ${remoteDownloads} -> ${localDownloads}.
  age.secrets = {
    seedbox-ssh-key = {
      file = ../../secrets/seedbox-ssh-key.age;
      owner = "seedbox-pull";
      inherit group;
    };

    # `user:password` for the slot's basic-auth proxy in front of qBittorrent.
    seedbox-qbittorrent-auth.file = ../../secrets/seedbox-qbittorrent-auth.age;
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
    # release. Only the arr categories come home; the slot's other folders stay.
    # `--size-only`: finished torrent files never change, and modtimes of
    # already-landed copies do not match the slot's, so size is the only
    # comparison that neither re-copies nor hashes. It also makes a copy of an
    # unfinished file permanent, and qBittorrent's files have their final size
    # from the first piece on, so `--min-age` alone is not enough. The slot's
    # qBittorrent appends `.!qB` to incomplete files (a WebUI setting, not
    # Nix) and renames each one when it completes; excluding them is what
    # makes "completed" true.
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
        rclone copy --inplace=false --size-only --min-age 1m --transfers 8 --multi-thread-streams 4 \
          --exclude '*.!qB' --include '/{sonarr,radarr}/**' "seedbox:${remoteDownloads}" "${localDownloads}"
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

    # AvistaZ upload comes from seeding fresh releases while they still have
    # leechers, and freeleech ones cost no ratio to fetch. New releases are
    # found through Prowlarr's AvistaZ indexer (it holds the tracker login)
    # and added to the slot under the `ratio` category, which the pull never
    # brings home. A torrent is deleted from the slot once it has seeded for
    # SEED_MINUTES; 14 days clears AvistaZ's hit-and-run rule (72 h + 2 h/GB)
    # for anything up to MAX_SIZE_GB. The site also frowns on leaving
    # low-seeded torrents, so one with fewer than MIN_OTHER_SEEDERS stays
    # until more show up. MAX_TOTAL_GB bounds the slot disk the category may
    # hold at once.
    services.seedbox-ratio-grab = {
      description = "Grab discounted AvistaZ releases on the seedbox for ratio";
      after = [
        "network-online.target"
        "prowlarr.service"
      ];
      wants = [ "network-online.target" ];
      environment = {
        PROWLARR_URL = "http://localhost:9696";
        PROWLARR_INDEXER_ID = "2";
        QBITTORRENT_URL = qbittorrent;
        CATEGORY = "ratio";
        SAVE_PATH = "${remoteDownloads}/ratio";
        SEED_MINUTES = "20160";
        MIN_OTHER_SEEDERS = "3";
        MAX_AGE_HOURS = "12";
        MAX_SIZE_GB = "100";
        MAX_TOTAL_GB = "300";
        MAX_DOWNLOAD_FACTOR = "0";
        # Fresh swarms are one slow uploader and a dozen leechers all at the
        # same progress; upload is re-serving pieces to as many of them as
        # possible, so the client's default 4 slots/torrent is the cap.
        UPLOAD_SLOTS = "200";
        UPLOAD_SLOTS_PER_TORRENT = "50";
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${ratioGrab}/bin/seedbox-ratio-grab";
        DynamicUser = true;
        StateDirectory = "seedbox-ratio-grab";
        LoadCredential = [
          "qbittorrent-auth:${config.age.secrets.seedbox-qbittorrent-auth.path}"
          "prowlarr-api-key:${config.age.secrets.prowlarr-api-key.path}"
        ];
      };
    };

    timers.seedbox-ratio-grab = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        # AvistaZ has no IRC announces, so being an early seeder means
        # polling. The site has blocked API clients for overload before
        # (RSS is what it sanctions for automation), so keep this modest.
        OnBootSec = "5m";
        OnUnitInactiveSec = "10m";
      };
    };
  };
}
