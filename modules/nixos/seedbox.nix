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

  # The remote is defined through the environment rather than a config file:
  # rclone rewrites its config file on every run, which a store path cannot be.
  rcloneRemote = {
    RCLONE_CONFIG = "/dev/null";
    RCLONE_CONFIG_SEEDBOX_TYPE = "sftp";
    RCLONE_CONFIG_SEEDBOX_HOST = host;
    RCLONE_CONFIG_SEEDBOX_USER = user;
    RCLONE_CONFIG_SEEDBOX_KEY_FILE = config.age.secrets.seedbox-ssh-key.path;
    RCLONE_CONFIG_SEEDBOX_KNOWN_HOSTS_FILE = "${knownHosts}";
    RCLONE_CONFIG_SEEDBOX_HOST_KEY_ALGORITHMS = "ssh-ed25519";
    # Never run md5sum on the slot: the shared HDD is what qBittorrent is
    # writing to.
    RCLONE_CONFIG_SEEDBOX_DISABLE_HASHCHECK = "true";
  };

  ratioGrab = pkgs.writers.writePython3Bin "seedbox-ratio-grab" {
    libraries = [ pkgs.python3Packages.requests ];
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./seedbox/ratio-grab.py);
in
{
  # A Whatbox slot, used for private-tracker torrents that need long seeding.
  # Its qBittorrent is the only download client in Sonarr and Radarr
  # (configured through their UIs) behind the slot's basic-auth proxy at
  # https://qbittorrent.freedgiraffe.box.ca; this module brings finished
  # files home so the usual import path applies, via a remote path mapping
  # of ${remoteDownloads} -> ${localDownloads}.
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
    # rclone sets the modtime of every directory it copies into, which only
    # the owner may do.
    tmpfiles.rules = map (d: "d ${localDownloads}${d} 2775 seedbox-pull ${group} -") [
      ""
      "/sonarr"
      "/radarr"
    ];

    # `sync` makes home mirror the slot's arr folders: once the arrs import a
    # torrent and remove it from the slot, its download copy disappears here
    # too (library imports are hardlinks, so nothing is lost). It only ever
    # writes at home; the slot is read. `--inplace=false` writes in-flight
    # files under a temp name so the arrs never see a half-copied release.
    # Only the arr categories come home; the slot's other folders stay.
    # `--size-only`: finished torrent files never change, and modtimes of
    # already-landed copies do not match the slot's, so size is the only
    # comparison that neither re-copies nor hashes. It also makes a copy of an
    # unfinished file permanent, and qBittorrent's files have their final size
    # from the first piece on, so `--min-age` alone is not enough. The slot's
    # qBittorrent appends `.!qB` to incomplete files (asserted by the ratio
    # grab below) and renames each one when it completes; excluding them is
    # what makes "completed" true.
    services.seedbox-pull = {
      description = "Pull completed seedbox downloads home";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      # A pull can run for hours; a switch that waited on it would block. The
      # timer picks up the new unit on its next run.
      restartIfChanged = false;
      path = [ pkgs.rclone ];
      environment = rcloneRemote // {
        RCLONE_CACHE_DIR = "/var/cache/seedbox-pull";
      };
      script = ''
        rclone sync --inplace=false --size-only --min-age 1m --transfers 8 --multi-thread-streams 4 \
          --filter '- *.!qB' --filter '+ /{sonarr,radarr}/**' --filter '- *' \
          "seedbox:${remoteDownloads}" "${localDownloads}"
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
      restartIfChanged = false;
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
        # Slot-wide qBittorrent settings the rest of this module relies on,
        # asserted on every run so a WebUI change cannot silently undo them.
        # Fresh swarms are one slow uploader and a dozen leechers all at the
        # same progress; upload is re-serving pieces to as many of them as
        # possible, so the default 4 upload slots/torrent is the cap. The
        # pull depends on incomplete files carrying `.!qB`; queueing would
        # leave grabbed torrents idle, and AvistaZ counts bonus only for
        # active ones.
        QBITTORRENT_PREFERENCES = builtins.toJSON {
          max_uploads = 200;
          max_uploads_per_torrent = 50;
          incomplete_files_ext = true;
          queueing_enabled = false;
        };
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
