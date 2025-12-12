{ ... }:

{
  users.users.oliver = {
    name = "oliver";
    home = "/Users/oliver";
  };

  system.primaryUser = "oliver";

  nix.enable = false;

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 4;
}
