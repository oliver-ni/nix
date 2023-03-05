{ config, pkgs, ... }:

{
  imports = [
    ../../modules/darwin/base.nix
    ../../modules/darwin/docker.nix
    ../../modules/darwin/python.nix
    ../../modules/darwin/redis.nix
  ];

  users.users.oliver = {
    name = "oliver";
    home = "/Users/oliver";
  };

  home-manager.users.oliver = import ./home.nix;

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 4;
}
