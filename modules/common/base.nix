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

  services.tailscale.enable = true;

  programs.zsh.enable = true;

  fonts.packages = with pkgs; [ raleway ];

  environment.systemPackages = with pkgs; [
    fzf
    kubectl
    kubectx
    git-branchless

    nixd

    comma-with-db
  ];
}
