{ pkgs, config, lib, ... }:

let
  cfg = config.oliver."1password";
in
{
  options.oliver."1password" = {
    enable = lib.mkEnableOption "1Password CLI and GUI";

    cliPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs._1password;
    };

    guiPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.brewCasks."1password";
    };
  };

  config = lib.mkIf cfg.enable {
    # 1Password.app doesn't like being run outside of /Applications, so we have
    # to copy the app over instead of the normal symlink in 'Nix Apps'.

    environment.systemPackages = [ cfg.cliPackage ];

    system.activationScripts.applications.text = ''
      echo "copying 1Password.app to /Applications..." >&2
      ${lib.getBin pkgs.rsync}/bin/rsync -a \
        ${cfg.guiPackage}/Applications/1Password.app/ /Applications/1Password.app
    '';
  };
}
