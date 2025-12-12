{ ... }:

{
  users.users.oliver = {
    name = "oliver";
    home = "/Users/oliver";
  };

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 4;
}
