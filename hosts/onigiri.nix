{ ... }:

{
  users.users.oliver = {
    name = "oliver";
    home = "/Users/oliver";
  };

  # oliver."1password".enable = true;

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 4;
}
