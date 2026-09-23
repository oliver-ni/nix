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

    @assets path /assets/*
    header @assets Cache-Control "public, max-age=31536000, immutable"

    handle {
      try_files {path} /index.html
      file_server
    }
  '';
}
