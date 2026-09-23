{ inputs, pkgs, ... }:

let
  # oliver-ni/jellyfin-client: a static SPA. The Jellyfin URL is baked in so
  # sign-in skips the address step; Seerr is reached through the same origin
  # under /seerr.
  client = inputs.jellyfin-client.packages.${pkgs.stdenv.hostPlatform.system}.default.override {
    jellyfinUrl = "https://jellyfin.ochazuke.org";
    brandMark = "🍵";
  };
in
{
  services.caddy.virtualHosts."ochazuke.org".extraConfig = ''
    tls {
      dns cloudflare {env.CF_API_TOKEN}
      resolvers 1.1.1.1
    }

    root * ${client}

    handle_path /seerr/* {
      reverse_proxy localhost:5055
    }

    # Read-only Sonarr diagnostics for the requests page, keyed server-side
    # and open only to browsers holding a Seerr session (Sonarr itself has no
    # login). Mirrors docker/proxies.sh in the client repo.
    @sonarr {
      method GET
      path_regexp ^/sonarr/api/v3/(system/status|series/[0-9]+|episode|queue)$
    }
    handle @sonarr {
      forward_auth localhost:5055 {
        # The trailing `?` drops the client's query string, which Seerr's
        # validator would otherwise reject as unknown parameters.
        uri /api/v1/auth/me?
      }
      uri strip_prefix /sonarr
      reverse_proxy localhost:8989 {
        header_up X-Api-Key {env.SONARR_API_KEY}
        header_up -Cookie
      }
    }
    handle /sonarr/* {
      respond 404
    }

    @assets path /assets/*
    header @assets Cache-Control "public, max-age=31536000, immutable"

    handle {
      try_files {path} /index.html
      file_server
    }
  '';
}
