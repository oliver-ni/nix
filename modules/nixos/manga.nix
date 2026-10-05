{ pkgs, ... }:

{
  # Two halves, like Sonarr + Jellyfin. Suwayomi is the fetching side: it runs
  # Mihon's source extensions server-side, tracks the library, downloads new
  # chapters on its update schedule and has its own (single-user, login-less)
  # reader, so it binds to loopback and is reached only through Caddy's
  # tailnet-only hostname. Komga is the sharing side: it serves the CBZs
  # Suwayomi writes with per-user accounts, read progress, a web reader and
  # OPDS, publicly at manga.<domain>. Chapters land on the pool; both
  # databases stay under /var/lib.
  services.suwayomi-server = {
    enable = true;
    group = "media";

    # Keiyoushi's listing is a protobuf "extension store" (repo.json ->
    # index.pb) with v1.6 extensions; the old index.min.json only carries
    # "update your app" stubs. nixpkgs' 2.1 predates both, so pin the current
    # stable jar until nixpkgs catches up.
    package = pkgs.suwayomi-server.overrideAttrs (
      finalAttrs: _: {
        version = "2.4.2366";
        src = pkgs.fetchurl {
          url = "https://github.com/Suwayomi/Suwayomi-Server/releases/download/v${finalAttrs.version}/Suwayomi-Server-v${finalAttrs.version}.jar";
          hash = "sha256-r5/rIK+dfr6eMHaebG68f8erHERziNQuAoCx2l/ge/0=";
        };
      }
    );

    settings.server = {
      ip = "127.0.0.1";
      port = 4567;
      downloadsPath = "/zfs78/media/manga";
      downloadAsCbz = true;
      autoDownloadNewChapters = true;
      extensionStores = [ "https://raw.githubusercontent.com/keiyoushi/extensions/repo/repo.json" ];
    };
  };

  # Libraries, users and scan schedules are Komga's own state (set in its UI);
  # the library root is /zfs78/media/manga/mangas, Suwayomi's
  # <source>/<title>/<chapter>.cbz tree.
  services.komga = {
    enable = true;
    group = "media";
    settings = {
      server = {
        address = "127.0.0.1";
        port = 25600;
      };

      # "Sign in with ochazuke account" (kanidm.nix). Komga matches people to
      # its own users by email and creates the missing ones on first login.
      komga.oauth2-account-creation = true;
      spring.security.oauth2.client = {
        registration.ochazuke = {
          provider = "ochazuke";
          client-id = "komga";
          client-name = "ochazuke account";
          client-authentication-method = "none";
          scope = [
            "openid"
            "profile"
            "email"
          ];
        };
        provider.ochazuke = {
          issuer-uri = "https://accounts.ochazuke.org/oauth2/openid/komga";
          user-name-attribute = "preferred_username";
        };
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d /zfs78/media/manga 2775 root media -"
    "d /zfs78/media/manga/mangas 2775 root media -"
  ];
}
