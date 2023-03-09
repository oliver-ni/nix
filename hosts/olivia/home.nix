{ pkgs, ... }:

{
  imports = [
    ../../modules/home/kitty.nix
    ../../modules/home/neovim.nix
    ../../modules/home/zsh.nix
  ];

  home.stateVersion = "22.11";
}
