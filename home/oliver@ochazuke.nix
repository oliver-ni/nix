{ ... }:

{
  imports = [
    ../modules/home/cli.nix
    ../modules/home/zsh.nix
  ];

  home.username = "oliver";
  home.homeDirectory = "/home/oliver";
  home.stateVersion = "26.05";
}
