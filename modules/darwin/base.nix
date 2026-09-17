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
    # direnv is managed by home-manager instead
    zsh.enableCompletion = false;
    zsh.enableBashCompletion = false;
    zsh.promptInit = "";
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
}
