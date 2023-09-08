{ pkgs, inputs, ... }:

{
  nix = {
    registry = {
      nixpkgs.flake = inputs.nixpkgs;
      nixpkgs-python.flake = inputs.nixpkgs-python;
    };
    settings = {
      experimental-features = "nix-command flakes";
      substituters = [ "https://nixpkgs-python.cachix.org" ];
      trusted-substituters = [ "https://nixpkgs-python.cachix.org" ];
      trusted-public-keys = [ "nixpkgs-python.cachix.org-1:hxjI7pFxTyuTHn2NkvWCrAUcNZLNS3ZAvfYNuYifcEU=" ];
    };
  };

  services.nix-daemon.enable = true;
  services.activate-system.enable = true;
  programs.zsh.enable = true;
  security.pam.enableSudoTouchIdAuth = true;

  environment.systemPackages = with pkgs; [
    bat
    nixpkgs-fmt
    tmux
    wget

    kubectl
    kubectx
    kubeseal
    kubetail
    kubernetes-helm
    krew

    jdk17
    nodejs-18_x
    nodePackages.pnpm
    vsce
    rustup

    elixir_1_14
    elixir-ls
    erlangR25

    edgedb
    mongosh
    zola

    gh
    google-cloud-sdk
    stripe-cli
    s3cmd
    teleport

    hyperfine
    imagemagick
    pandoc
    pre-commit
    scc

    git
    git-lfs

    ccache
    cmake
    clang-tools

    typst
    _1password
    cachix
  ];
}
