{ ... }:

{
  users.users.oliver.home = "/Users/oliver";

  system.primaryUser = "oliver";

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 4;
}
