{ pkgs, ... }:

{
  home.packages = with pkgs; [
    fzf
    kubectl
    kubectx
    git-branchless
    gh
    jujutsu

    rustup
    nixfmt
    _1password-cli

    comma-with-db
  ];
}
