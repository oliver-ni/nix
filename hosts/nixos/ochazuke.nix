{ pkgs, ... }:

{
  imports = [
    ../../hardware/ochazuke.nix
    ../../modules/nixos/home-assistant.nix
    ../../modules/nixos/photos.nix
    ../../modules/nixos/media.nix
    ../../modules/nixos/jellyfin-client.nix
    ../../modules/nixos/jfa-go.nix
    ../../modules/nixos/lolesports-kiosk.nix
    ../../modules/nixos/proxy.nix
    ../../modules/nixos/seedbox.nix
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

  # Long-haul transfers (the Amsterdam seedbox, remote Jellyfin streams) fold
  # under cubic on any packet loss; BBR keeps the window open.
  boot.kernelModules = [ "tcp_bbr" ];
  boot.kernel.sysctl."net.ipv4.tcp_congestion_control" = "bbr";

  users.users.oliver = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHXDswYZKz5teffU3I4kxl1Rr4Z+9hdywNsBypb//Icv"
    ];
  };

  # Tailscale SSH answers port 22 for tailnet peers; who may log in as whom is
  # the tailnet policy's `ssh` section (ochazuke carries tag:server). LAN SSH
  # still reaches sshd and the keys above.
  services.tailscale.extraSetFlags = [ "--ssh" ];

  security.sudo.wheelNeedsPassword = false;
  home-manager.users.oliver = import ../../home/${"oliver@ochazuke"}.nix;

  system.stateVersion = "26.05";
}
