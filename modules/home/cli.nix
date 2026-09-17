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
    _1password-cli

    comma-with-db
  ];
}
