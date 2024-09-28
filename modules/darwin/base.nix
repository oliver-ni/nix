{ pkgs, lib, inputs, ... }:

{
  nix = {
    package = pkgs.lix;
    channel.enable = false;
    registry = lib.mapAttrs (_: value: { flake = value; }) inputs;
    settings = {
      experimental-features = "nix-command flakes";
      nix-path = lib.mapAttrsToList (name: _: "${name}=flake:${name}") inputs;
    };
  };

  services.tailscale.enable = true;
  services.nix-daemon.enable = true;
  security.pam.enableSudoTouchIdAuth = true;

  programs.zsh.enable = true;

  fonts.packages = with pkgs; [ raleway ];

  environment.systemPackages = with pkgs; [
    fzf
    kubectl
    kubectx
    git-branchless

    utm
    qemu
    nixd

    comma-with-db

    # GUI Apps
    arc-browser
    raycast
    brewCasks.discord
    brewCasks.signal
    brewCasks.zed
    brewCasks.cleanshot
    brewCasks."affinity-designer@1"
  ];
}
