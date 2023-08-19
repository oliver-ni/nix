{ pkgs, ... }:

{
  services.nix-daemon.enable = true;
  programs.zsh.enable = true;
  security.pam.enableSudoTouchIdAuth = true;
  nix.settings = {
    experimental-features = "nix-command flakes";
  };

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
  ];
}
