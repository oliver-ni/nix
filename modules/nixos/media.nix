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
      UMask = "0002";
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
  # branch, so pin it to avoid a future flake update silently pulling 590.
  hardware = {
    graphics.enable = true;

    nvidia = {
      package = config.boot.kernelPackages.nvidiaPackages.stable;
      open = false;
      modesetting.enable = true;
      nvidiaSettings = false;
    };
  };

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
      openFirewall = true;
      settings.auth.method = "External";
    };

    radarr = {
      inherit group;
      enable = true;
      openFirewall = true;
      settings.auth.method = "External";
    };

    prowlarr = {
      enable = true;
      openFirewall = true;
      settings.auth.method = "External";
    };

    qbittorrent = {
      inherit group;
      enable = true;
      openFirewall = true;
      webuiPort = 8080;

      serverConfig = {
        LegalNotice.Accepted = true;

        Preferences = {
          WebUI = {
            Username = "oliver";
            Password_PBKDF2 = "@ByteArray(4ymIqSh4kJCi4ggUdRXEfA==:rBBpEBessypr2kwS8L2I9Czra2Fw+o9kBj0HJa5eUaxA6SAflEWROohw4hPTr6MDQ1CN4kBGygQaAcqwI0KDvA==)";
            AuthSubnetWhitelistEnabled = true;
            AuthSubnetWhitelist = "192.168.1.0/24";
          };

          Downloads.SavePath = "${mediaDir}/downloads";
        };

        BitTorrent.Session.DefaultSavePath = "${mediaDir}/downloads";
      };
    };

    recyclarr = {
      enable = true;

      configuration.sonarr.anime = {
        base_url = "http://localhost:8989";
        api_key._secret = config.age.secrets.sonarr-api-key.path;
        quality_definition.type = "anime";
        delete_old_custom_formats = true;
        replace_existing_custom_formats = true;
        include = [
          { template = "sonarr-quality-definition-anime"; }
          { template = "sonarr-v4-quality-profile-anime"; }
          { template = "sonarr-v4-custom-formats-anime"; }
        ];
      };
    };
  };

  systemd = {
    # Shared group + setgid dirs + UMask 0002 lets every service read and
    # rename each other's files, which hardlink imports depend on.
    tmpfiles.rules = map (d: "d ${mediaDir}/${d} 2775 root ${group} -") [
      "downloads"
      "downloads/anime"
      "downloads/tv"
      "downloads/movies"
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
