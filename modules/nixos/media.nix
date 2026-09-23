{ config, lib, ... }:

let
  mediaDir = "/zfs78/media";
  group = "media";

  # The *arr services take their API key via an environment variable, but the
  # age secret holds only the bare key so Recyclarr can read it too. A oneshot
  # ordered before each service writes the env file; systemd reads
  # EnvironmentFile before ExecStartPre, so preStart is too late.
  arrApiKeyUnits = name: {
    ${name}.serviceConfig = {
      EnvironmentFile = "/run/${name}/env";
      UMask = lib.mkForce "0002";
    };

    "${name}-env" = {
      before = [ "${name}.service" ];
      requiredBy = [ "${name}.service" ];

      serviceConfig = {
        Type = "oneshot";
        RuntimeDirectory = name;
        RuntimeDirectoryPreserve = true;
      };

      script = ''
        umask 077
        printf '${lib.toUpper name}__AUTH__APIKEY=%s\n' "$(cat ${
          config.age.secrets."${name}-api-key".path
        })" > /run/${name}/env
      '';
    };
  };
in
{
  # The arrs and qBittorrent run without their own login, so they bind to
  # loopback and are reached only through Caddy's tailnet-only hostnames.
  users = {
    groups.${group} = { };
    users.oliver.extraGroups = [ group ];
  };

  age.secrets = {
    sonarr-api-key.file = ../../secrets/sonarr-api-key.age;
    radarr-api-key.file = ../../secrets/radarr-api-key.age;
    prowlarr-api-key.file = ../../secrets/prowlarr-api-key.age;
  };

  # NVENC transcoding on the GTX 1060. Pascal support ended with the 580
  # branch; newer drivers refuse to load on it.
  hardware = {
    graphics.enable = true;

    nvidia = {
      package = config.boot.kernelPackages.nvidiaPackages.legacy_580;
      open = false;
      nvidiaSettings = false;
    };
  };

  # Jellyfin and Seerr are public through the proxy; the admin UIs are only
  # reachable over the tailnet.
  services = {
    xserver.videoDrivers = [ "nvidia" ];

    jellyfin = {
      inherit group;
      enable = true;
      openFirewall = true;
    };

    sonarr = {
      inherit group;
      enable = true;
      settings = {
        auth.method = "External";
        server.bindAddress = "127.0.0.1";
      };
    };

    radarr = {
      inherit group;
      enable = true;
      settings = {
        auth.method = "External";
        server.bindAddress = "127.0.0.1";
      };
    };

    prowlarr = {
      enable = true;
      settings = {
        auth.method = "External";
        server.bindAddress = "127.0.0.1";
      };
    };

    qbittorrent = {
      inherit group;
      enable = true;

      serverConfig = {
        LegalNotice.Accepted = true;
        BitTorrent.Session.DefaultSavePath = "${mediaDir}/torrents";

        Preferences = {
          Downloads.SavePath = "${mediaDir}/torrents";
          WebUI.Address = "127.0.0.1";
          WebUI.LocalHostAuth = false;
          # Dead public batches (0 seeds) must not hold the active-download
          # slots hostage; a torrent under 50 KiB/s for a minute stops counting.
          Queueing = {
            MaxActiveDownloads = 5;
            MaxActiveTorrents = 10;
            IgnoreSlowTorrents = true;
            SlowTorrentsDownloadRate = 50;
            SlowTorrentsInactivityTimer = 60;
          };
        };
      };
    };

    seerr.enable = true;

    recyclarr = {
      enable = true;

      # TRaSH profiles, with custom formats synced automatically from the
      # trash_ids. "[Anime] Remux-1080p" is the default for anime series;
      # "WEB-1080p" is for regular TV, whose releases score far below the
      # anime profile's 100-point minimum.
      configuration = {
        sonarr.tv = {
          base_url = "http://localhost:8989";
          api_key._secret = config.age.secrets.sonarr-api-key.path;
          quality_definition.type = "anime";
          delete_old_custom_formats = true;
          quality_profiles = [
            {
              trash_id = "20e0fc959f1f1704bed501f23bdae76f";
              reset_unmatched_scores.enabled = true;
            }
            {
              trash_id = "72dae194fc92bf828f32cde7744e51a1";
              reset_unmatched_scores.enabled = true;
            }
          ];
        };

        # TRaSH's "Remux 2160p (Combined)" profile for movies with official UHD
        # releases: 2160p first, 1080p fallback. The anime filters keep fan
        # upscales and raw/LQ groups from counting as upgrades.
        radarr.movies = {
          base_url = "http://localhost:7878";
          api_key._secret = config.age.secrets.radarr-api-key.path;
          quality_definition.type = "movie";
          delete_old_custom_formats = true;
          quality_profiles = [
            {
              trash_id = "d1d310673359205736b4b84acd5ea8c8";
              reset_unmatched_scores.enabled = true;
            }
          ];
          custom_formats = [
            {
              trash_ids = [
                "bfd8eb01832d646a0a89c4deb46f8564" # Upscaled
                "06b6542a47037d1e33b15aa3677c2365" # Anime Raws
                "b0fdc5897f68c9a68c70c25169f77447" # Anime LQ Groups
              ];
              assign_scores_to = [
                {
                  trash_id = "d1d310673359205736b4b84acd5ea8c8";
                  score = -10000;
                }
              ];
            }
          ];
        };
      };
    };
  };

  systemd = {
    # Shared group + setgid dirs + UMask 0002 lets every service read and
    # rename each other's files, which hardlink imports depend on.
    tmpfiles.rules = map (d: "d ${mediaDir}/${d} 2775 root ${group} -") [
      "torrents"
      "torrents/anime"
      "torrents/tv"
      "torrents/movies"
      "library"
      "library/anime"
      "library/tv"
      "library/movies"
    ];

    services = {
      jellyfin.serviceConfig.UMask = lib.mkForce "0002";
      qbittorrent.serviceConfig.UMask = "0002";
    }
    // arrApiKeyUnits "sonarr"
    // arrApiKeyUnits "radarr"
    // arrApiKeyUnits "prowlarr";
  };
}
