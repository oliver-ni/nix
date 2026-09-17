{ config, lib, ... }:

let
  mediaDir = "/zfs78/media";
  group = "media";

  # The *arr services take their API key via an environment variable, but the
  # age secret holds only the bare key so Recyclarr can read it too. Bridge the
  # two with a runtime env file.
  arrApiKey = name: {
    age.secrets."${name}-api-key".file = ../../secrets/${name}-api-key.age;

    systemd.services.${name} = {
      serviceConfig = {
        RuntimeDirectory = name;
        EnvironmentFile = "-/run/${name}/env";
        UMask = "0002";
      };
      preStart = ''
        printf '${lib.toUpper name}__AUTH__APIKEY=%s\n' "$(cat ${
          config.age.secrets."${name}-api-key".path
        })" > /run/${name}/env
      '';
    };
  };
in
{
  imports = map arrApiKey [
    "sonarr"
    "radarr"
    "prowlarr"
  ];

  users.groups.${group} = { };
  users.users.oliver.extraGroups = [ group ];

  systemd.tmpfiles.rules = map (d: "d ${mediaDir}/${d} 2775 root ${group} -") [
    "downloads"
    "downloads/anime"
    "downloads/tv"
    "downloads/movies"
    "library"
    "library/anime"
    "library/tv"
    "library/movies"
  ];

  # NVENC transcoding on the GTX 1060. Pascal support ended with the 580
  # branch, so pin it to avoid a future flake update silently pulling 590.
  hardware.graphics.enable = true;
  hardware.nvidia = {
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    open = false;
    modesetting.enable = true;
    nvidiaSettings = false;
  };
  services.xserver.videoDrivers = [ "nvidia" ];

  services.jellyfin = {
    enable = true;
    inherit group;
    openFirewall = true;
  };
  systemd.services.jellyfin.serviceConfig.UMask = lib.mkForce "0002";

  services.sonarr = {
    enable = true;
    inherit group;
    openFirewall = true;
    settings.auth.method = "External";
  };

  services.radarr = {
    enable = true;
    inherit group;
    openFirewall = true;
    settings.auth.method = "External";
  };

  services.prowlarr = {
    enable = true;
    openFirewall = true;
    settings.auth.method = "External";
  };

  services.qbittorrent = {
    enable = true;
    inherit group;
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
  systemd.services.qbittorrent.serviceConfig.UMask = "0002";

  services.recyclarr = {
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
}
