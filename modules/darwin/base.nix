{ pkgs, ... }:

{
  services.nix-daemon.enable = true;
  security.pam.enableSudoTouchIdAuth = true;

  fonts.packages = with pkgs; [ raleway ];

  environment.systemPackages = with pkgs; [
    utm
    qemu

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
