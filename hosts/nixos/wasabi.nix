{ lib, pkgs, ... }:

{
  imports = [
    ../../hardware/wasabi.nix
    ../../modules/nixos/tailscale.nix
    ../../modules/nixos/zfs.nix
  ];

  networking = {
    hostName = "wasabi";
    hostId = "8425e349";
  };

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  # nouveau faults on this GTX 750 Ti (PRIVRING MMIO) and blanks every output;
  # without it the console stays on the firmware framebuffer.
  boot.blacklistedKernelModules = [ "nouveau" ];

  # Quick tunnel for remote SSH; its hostname changes on every start and is
  # printed to the console.
  systemd.services.cloudflared-ssh = {
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];

    serviceConfig = {
      ExecStart = "${lib.getExe pkgs.cloudflared} tunnel --no-autoupdate --url ssh://localhost:22";
      DynamicUser = true;
      Restart = "on-failure";
      StandardError = "journal+console";
    };
  };

  users.users.oliver = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHXDswYZKz5teffU3I4kxl1Rr4Z+9hdywNsBypb//Icv"
    ];
  };

  security.sudo.wheelNeedsPassword = false;
  home-manager.users.oliver = import ../../home/${"oliver@wasabi"}.nix;

  system.stateVersion = "26.11";
}
