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

      virtualHosts."admin.accounts.${domain}".extraConfig = ''
        tls {
          dns cloudflare {env.CF_API_TOKEN}
          resolvers 1.1.1.1
        }

        @tailnet remote_ip 100.64.0.0/10 fd7a:115c:a1e0::/48
        handle @tailnet {
          reverse_proxy localhost:8056
        }

        handle {
          respond 404
        }
      '';

      # One wildcard certificate via DNS-01 covers every hostname, so adding a
      # service never triggers a new issuance (which needs the fresh name to be
      # visible to public resolvers before it can succeed). The apex is served
      # by jellyfin-client.nix.
      extraConfig = ''
        *.${domain} {
          tls {
            dns cloudflare {env.CF_API_TOKEN}
            resolvers 1.1.1.1
          }

          @jellyfin host jellyfin.${domain}
          handle @jellyfin {
            reverse_proxy localhost:8096
          }

          # Seerr's own UI is superseded by the client at the apex.
          @requests host requests.${domain}
          handle @requests {
            redir https://${domain}{uri}
          }

          @accounts host accounts.${domain}
          handle @accounts {
            @inviteRead {
              method GET HEAD
              path /invite/* /css/* /js/* /fonts/* /lang/* /captcha/gen/* /captcha/img/* /favicon* /apple-touch-icon.png /site.webmanifest /safari-pinned-tab.svg /android-chrome-*.png
            }
            handle @inviteRead {
              reverse_proxy localhost:8056
            }

            @inviteWrite {
              method POST
              path /user/invite /captcha/verify/*
            }
            handle @inviteWrite {
              reverse_proxy localhost:8056
            }

            handle {
              respond 404
            }
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
