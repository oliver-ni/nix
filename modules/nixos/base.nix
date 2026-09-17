{ config, inputs, lib, pkgs, ... }:

{
  nix = {
    channel.enable = false;
    registry = lib.mapAttrs (_: value: { flake = value; }) inputs;
    nixPath = lib.mapAttrsToList (name: _: "${name}=flake:${name}") inputs;
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      nix-path = config.nix.nixPath;
    };
  };

  networking.useNetworkd = true;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  programs.zsh.enable = true;
  environment.systemPackages = with pkgs; [ vim rsync ];

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    sharedModules = [ ../home/base.nix ];
  };
}
