{ config, pkgs, ... }:

let
  domain = "ochazuke.org";
in
{
  age.secrets.cloudflare-api-token.file = ../../secrets/cloudflare-api-token.age;

  networking.firewall.allowedTCPPorts = [
    80
    443
  ];

  services = {
    cloudflare-dyndns = {
      enable = true;
      apiTokenFile = config.age.secrets.cloudflare-api-token.path;
      domains = [ domain ];
    };

    caddy = {
      enable = true;
      package = pkgs.caddy.withPlugins {
        plugins = [ "github.com/caddy-dns/cloudflare@v0.2.4" ];
        hash = "sha256-dQvk6ezY6TQ1J7PjhCXnThF/SqVgPwBO8/RXzHCY+js=";
      };
      environmentFile = "/run/caddy/env";

      # One wildcard cert via DNS-01, so no port 80 challenge and no
      # per-service certificate churn.
      globalConfig = ''
        acme_dns cloudflare {env.CF_API_TOKEN}
      '';

      virtualHosts = {
        ${domain}.extraConfig = "redir https://jellyfin.${domain}";
        "jellyfin.${domain}".extraConfig = "reverse_proxy localhost:8096";
        "requests.${domain}".extraConfig = "reverse_proxy localhost:5055";

        "sonarr.${domain}".extraConfig = ''
          import lan_only 8989
        '';
        "radarr.${domain}".extraConfig = ''
          import lan_only 7878
        '';
        "prowlarr.${domain}".extraConfig = ''
          import lan_only 9696
        '';
        "qbittorrent.${domain}".extraConfig = ''
          import lan_only 8080
        '';
      };

      # Everything except Jellyfin is only for use from home.
      extraConfig = ''
        (lan_only) {
          @lan remote_ip 192.168.1.0/24
          handle @lan {
            reverse_proxy localhost:{args[0]}
          }
          respond 403
        }
      '';
    };
  };

  systemd.services = {
    # The upstream unit only orders after network.target, so the boot run
    # fires before DHCP finishes and fails until the timer's next tick.
    cloudflare-dyndns = {
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
    };

    # Caddy reads the token from an environment variable, but cloudflare-dyndns
    # wants the bare file, so the age secret stays bare and a oneshot bridges.
    caddy-env = {
      before = [ "caddy.service" ];
      requiredBy = [ "caddy.service" ];

      serviceConfig = {
        Type = "oneshot";
        RuntimeDirectory = "caddy";
        RuntimeDirectoryPreserve = true;
      };

      script = ''
        umask 077
        printf 'CF_API_TOKEN=%s\n' "$(cat ${config.age.secrets.cloudflare-api-token.path})" > /run/caddy/env
      '';
    };
  };
}
