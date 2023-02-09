{ pkgs, ... }:

{
  imports = [
    ./modules/neovim.nix
    ./modules/python.nix
    ./modules/zsh.nix
  ];

  home = {
    username = "oliver";
    homeDirectory = "/Users/oliver";
    stateVersion = "22.11";

    packages = with pkgs; [
      kubectl
      gh
      stripe-cli
      tmux
      pandoc
      nodejs-18_x
      kubectx
      bat
      hyperfine
      imagemagick
      kubetail
      kubeseal
      mongosh
      pre-commit
      scc
      unixtools.watch
      google-cloud-sdk
      poetry
      s3cmd
    ];
  };

  programs.home-manager.enable = true;
}

