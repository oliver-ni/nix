{ pkgs, ... }:

{
  imports = [
    ../../modules/home/zsh
    ../../modules/home/kitty.nix
    ../../modules/home/neovim.nix
  ];

  home.stateVersion = "22.11";
}
