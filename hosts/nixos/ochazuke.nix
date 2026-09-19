{ pkgs, ... }:

{
  imports = [
    ../../hardware/ochazuke.nix
    ../../modules/nixos/media.nix
    ../../modules/nixos/jfa-go.nix
    ../../modules/nixos/proxy.nix
    ../../modules/nixos/tailscale.nix
    ../../modules/nixos/zfs.nix
  ];

  networking = {
    hostName = "ochazuke";
    hostId = "c9fb946d";
  };

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  boot.zfs.extraPools = [ "zfs78" ];

  users.users.oliver = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHXDswYZKz5teffU3I4kxl1Rr4Z+9hdywNsBypb//Icv"
    ];
  };

  security.sudo.wheelNeedsPassword = false;
  home-manager.users.oliver = import ../../home/${"oliver@ochazuke"}.nix;

  system.stateVersion = "26.05";
}
