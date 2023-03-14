{ pkgs, ... }:

{
  services.nix-daemon.enable = true;
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

    jdk
    nodejs-18_x
    rustup

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
  ];
}
