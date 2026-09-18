{ config, pkgs, ... }:

let
  abyss = pkgs.fetchFromGitHub {
    owner = "AumGupta";
    repo = "abyss-jellyfin";
    tag = "v1.2.3";
    hash = "sha256-tzXgVk1HKiBi5BAibD8LjJ/qTBEEGZjDEpV1LIOyeVg=";
  };

  web = pkgs.jellyfin-web.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      web="$out/share/jellyfin-web"
      mkdir -p "$web/ui"
      cp ${abyss}/abyss.css "$web/ui/abyss.css"
      cp ${abyss}/scripts/spotlight/{spotlight.html,spotlight.css,spotlight-loader.js} "$web/ui/"
      substituteInPlace "$web/index.html" \
        --replace-fail '</body>' '<script src="ui/spotlight-loader.js" data-abyss-spotlight></script></body>'
    '';
  });

  branding = pkgs.writeText "branding.xml" ''
    <?xml version="1.0" encoding="utf-8"?>
    <BrandingOptions>
      <CustomCss>@import url("ui/abyss.css");</CustomCss>
    </BrandingOptions>
  '';
in
{
  services.jellyfin.package = pkgs.jellyfin.override { jellyfin-web = web; };

  # Seed on first boot; Jellyfin owns the file after that. Existing installs
  # get the same CSS via the Branding API once.
  systemd.tmpfiles.rules = [
    "d ${config.services.jellyfin.configDir} 0750 jellyfin media -"
    "C ${config.services.jellyfin.configDir}/branding.xml 0640 jellyfin media - ${branding}"
  ];
}
