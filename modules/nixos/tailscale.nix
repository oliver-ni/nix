{ config, ... }:

# The tailnet is trusted like the LAN. Admin UIs are reached through Caddy's
# tailnet-only hostnames in proxy.nix; the services themselves bind loopback.
{
  services.tailscale = {
    enable = true;
    openFirewall = true;
  };

  networking.firewall.trustedInterfaces = [ config.services.tailscale.interfaceName ];
}
