{
  config,
  inputs,
  lib,
  ...
}:

{
  nix = {
    enable = false;
    registry = lib.mapAttrs (_: value: { flake = value; }) inputs;
  };

  environment.etc."nix/registry.json".text = builtins.toJSON {
    version = 2;
    flakes = lib.mapAttrsToList (_: value: { inherit (value) from to exact; }) config.nix.registry;
  };

  security.pam.services.sudo_local.touchIdAuth = true;

  programs.zsh = {
    # direnv is managed by home-manager instead
    enableCompletion = false;
    enableBashCompletion = false;
    promptInit = "";
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
