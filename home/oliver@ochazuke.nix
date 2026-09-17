{ ... }:

{
  imports = [
    ../modules/home/cli.nix
    ../modules/home/zsh.nix
  ];

  home.stateVersion = "26.05";
}
