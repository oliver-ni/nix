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

      # One wildcard certificate via DNS-01 covers every hostname, so adding a
      # service never triggers a new issuance (which needs the fresh name to be
      # visible to public resolvers before it can succeed).
      extraConfig = ''
        ${domain}, *.${domain} {
          tls {
            dns cloudflare {env.CF_API_TOKEN}
            resolvers 1.1.1.1
          }

          @root host ${domain}
          handle @root {
            redir https://jellyfin.${domain}
          }

          @jellyfin host jellyfin.${domain}
          handle @jellyfin {
            reverse_proxy localhost:8096
          }

          @requests host requests.${domain}
          handle @requests {
            reverse_proxy localhost:5055
          }

          # Everything else is only for use from home.
          @lan remote_ip 192.168.1.0/24

          @sonarr host sonarr.${domain}
          handle @sonarr {
            reverse_proxy @lan localhost:8989
            respond 403
          }

          @radarr host radarr.${domain}
          handle @radarr {
            reverse_proxy @lan localhost:7878
            respond 403
          }

          @prowlarr host prowlarr.${domain}
          handle @prowlarr {
            reverse_proxy @lan localhost:9696
            respond 403
          }

          @qbittorrent host qbittorrent.${domain}
          handle @qbittorrent {
            reverse_proxy @lan localhost:8080
            respond 403
          }

          respond 404
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
