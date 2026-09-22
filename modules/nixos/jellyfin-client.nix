{ inputs, pkgs, ... }:

let
  # oliver-ni/jellyfin-client: a static SPA. The Jellyfin URL is entered at
  # login; Seerr is reached through the same origin under /seerr.
  client = pkgs.buildNpmPackage {
    pname = "jellyfin-client";
    version = inputs.jellyfin-client.shortRev or "dirty";
    src = inputs.jellyfin-client;
    npmDepsHash = "sha256-jHjJ3urABWj3n23oS8dEPKm1K6pLzK88Ut2FzfBh3Q0=";

    # patch-package runs from the postinstall hook against the vendored
    # node_modules, which is exactly what we want.
    installPhase = ''
      runHook preInstall
      cp -r dist $out
      runHook postInstall
    '';
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
