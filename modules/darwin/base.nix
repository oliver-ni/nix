{ pkgs, lib, inputs, ... }:

{
  nix = {
    package = pkgs.lix;
    channel.enable = false;
    registry = lib.mapAttrs (_: value: { flake = value; }) inputs;
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      nix-path = lib.mapAttrsToList (name: _: "${name}=flake:${name}") inputs;
    };
  };

  security.pam.services.sudo_local.touchIdAuth = true;

  programs = {
    direnv.enable = true;
  };

  homebrew = {
    enable = true;
    casks = [
      "1password"
      "discord"
      "ghostty"
      "raycast"
      "zed"
      "zen"
    ];
  };

  environment.systemPackages = with pkgs; [
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
