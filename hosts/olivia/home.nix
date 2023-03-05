{ pkgs, ... }:

{
  imports = [
    ../../modules/home/neovim.nix
    ../../modules/home/zsh.nix
  ];

  home.stateVersion = "22.11";
}
