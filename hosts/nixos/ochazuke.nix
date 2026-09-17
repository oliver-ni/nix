{ pkgs, ... }:

{
  imports = [
    ../../hardware/ochazuke.nix
    ../../modules/nixos/zfs.nix
  ];

  networking = {
    hostName = "ochazuke";
    hostId = "c9fb946d";
    useDHCP = false;
    interfaces.enp4s0.useDHCP = true;
  };

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/BOOT";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
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
