{ config, pkgs, ... }:

{
  imports = [ ../../modules/darwin/base.nix ];

  users.users.oliver = {
    name = "oliver";
    home = "/Users/oliver";
  };

  home-manager.users.oliver = import ./home.nix;

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 4;
}
