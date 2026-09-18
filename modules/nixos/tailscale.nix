{ config, ... }:

# The admin UIs (Sonarr, Radarr, Prowlarr, qBittorrent) are reachable only
# over the tailnet, on their plain ports.
{
  services.tailscale = {
    enable = true;
    openFirewall = true;
  };

  networking.firewall.trustedInterfaces = [ config.services.tailscale.interfaceName ];
}
