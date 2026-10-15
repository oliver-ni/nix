{ config, pkgs, ... }:

let
  komfConfig = (pkgs.formats.yaml { }).generate "application.yml" {
    komga = {
      baseUri = "http://127.0.0.1:25600";
      komgaUser = "komf@ochazuke.org";
      # Without this Komf only acts on manual requests through its own API.
      eventListener.enabled = true;
      # Replace Komga's page-one thumbnail with the provider's cover art.
      metadataUpdate.default.seriesCovers = true;
    };
    metadataProviders.defaultProviders = {
      # Providers are off unless enabled; the lowest priority is tried first
      # and the first match wins. AniList first for its large covers and
      # because its link lets the client fetch banner art; MangaUpdates
      # covers the obscure titles AniList lacks.
      aniList.enabled = true;
      mangaUpdates = {
        enabled = true;
        priority = 20;
      };
    };
  };

  mangaRequests = pkgs.writers.writePython3Bin "manga-requests" {
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./manga/requests.py);

  komf = pkgs.fetchurl {
    url = "https://github.com/Snd-R/komf/releases/download/2.1.0/komf-2.1.0.jar";
    hash = "sha256-J2AitFV42TPoBHvmO/3UEjyAl53tiy8JhlB/2vCEAJM=";
  };
in

{
  # Two halves, like Sonarr + Jellyfin. Suwayomi is the fetching side: it runs
  # Mihon's source extensions server-side, tracks the library, downloads new
  # chapters on its update schedule and has its own (single-user, login-less)
  # reader, so it binds to loopback and is reached only through Caddy's
  # tailnet-only hostname. Komga is the sharing side: it serves the CBZs
  # Suwayomi writes with per-user accounts, read progress, a web reader and
  # OPDS, publicly at komga.<domain>; Komf below fills in its metadata.
  # Chapters land on the pool; all three databases stay under /var/lib.
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
      # Nobody reads in Suwayomi (Komga is the reader), so every title counts
      # as unstarted with unread chapters, which these default to skipping in
      # library updates and auto-downloads.
      excludeUnreadChapters = false;
      excludeNotStarted = false;
      excludeEntryWithUnreadChapters = false;
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
      # The Manga tab in jellyfin-client (ochazuke.org) calls this API from the
      # browser with the session cookie; same site, so the cookie is sent.
      komga.cors.allowed-origins = [ "https://ochazuke.org" ];
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

  # Komf fills in what Suwayomi's CBZs lack (cover, summary, genres, status,
  # provider links) by matching each new series on AniList/MangaUpdates and
  # writing the result into Komga over its API, as a Komga user of its own.
  # Not in nixpkgs; the release jar runs on the headless JRE. Komf wants a
  # directory it can write provider caches into, so the generated config is
  # copied into its state directory rather than read from the store.
  age.secrets.komga-komf-password.file = ../../secrets/komga-komf-password.age;

  systemd.services.komf = {
    description = "Komf metadata fetcher for Komga";
    after = [ "komga.service" ];
    wantedBy = [ "multi-user.target" ];
    preStart = "install -m 0600 ${komfConfig} /var/lib/komf/application.yml";
    script = ''
      KOMF_KOMGA_PASSWORD=$(cat "$CREDENTIALS_DIRECTORY/komga-password")
      export KOMF_KOMGA_PASSWORD
      exec ${pkgs.jre_headless}/bin/java -jar ${komf} /var/lib/komf
    '';
    serviceConfig = {
      DynamicUser = true;
      StateDirectory = "komf";
      WorkingDirectory = "/var/lib/komf";
      LoadCredential = "komga-password:${config.age.secrets.komga-komf-password.path}";
      Restart = "on-failure";
    };
  };

  # The client's Requests tab adds manga through this rather than Suwayomi's
  # API, which can also delete manga and change settings: search, add and list
  # only (see manga/requests.py). Caddy serves it at ochazuke.org/suwayomi to
  # browsers with a Seerr session (jellyfin-client.nix). It also has Komga scan
  # as soon as chapters land, as the Komga user `requests@ochazuke.org` (admin
  # role, which scans need; created by hand in Komga).
  age.secrets.komga-requests-password.file = ../../secrets/komga-requests-password.age;

  systemd.services.manga-requests = {
    description = "Manga requests for jellyfin-client";
    after = [
      "suwayomi-server.service"
      "komga.service"
    ];
    wantedBy = [ "multi-user.target" ];
    environment = {
      SUWAYOMI_URL = "http://127.0.0.1:4567";
      PORT = "4568";
      KOMGA_URL = "http://127.0.0.1:25600";
      KOMGA_USER = "requests@ochazuke.org";
      # Suwayomi source ids, preferred first: Weeb Central for the official,
      # complete releases of licensed series; MangaDex (EN) for the fan
      # translations of everything else.
      SOURCES = builtins.toJSON [
        "2131019126180322627"
        "2499283573021220255"
      ];
    };
    serviceConfig = {
      ExecStart = "${mangaRequests}/bin/manga-requests";
      DynamicUser = true;
      LoadCredential = "komga-password:${config.age.secrets.komga-requests-password.path}";
      Restart = "on-failure";
    };
  };

  systemd.tmpfiles.rules = [
    "d /zfs78/media/manga 2775 root media -"
    "d /zfs78/media/manga/mangas 2775 root media -"
  ];
}
