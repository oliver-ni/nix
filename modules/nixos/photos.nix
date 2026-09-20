{ ... }:

{
  services.samba = {
    enable = true;
    nmbd.enable = false;
    winbindd.enable = false;

    settings = {
      global = {
        "map to guest" = "Bad User";
        "smb ports" = "445";
        "hosts allow" = "127.0.0.1 ::1 192.168.1.0/24 100.64.0.0/10 fd7a:115c:a1e0::/48";
        "hosts deny" = "ALL";
        "load printers" = "no";
        "disable spoolss" = "yes";
        "vfs objects" = "fruit streams_xattr";
        "fruit:convert_adouble" = "no";
      };

      photos = {
        path = "/zfs78/photos";
        "guest ok" = "yes";
        "guest only" = "yes";
        "read only" = "yes";
      };
    };
  };

  systemd.services.samba-smbd.unitConfig.RequiresMountsFor = [ "/zfs78/photos" ];

  networking.firewall = {
    extraCommands = ''
      iptables -I nixos-fw -i enp4s0 -s 192.168.1.0/24 -p tcp --dport 445 -j nixos-fw-accept
    '';
    extraStopCommands = ''
      iptables -D nixos-fw -i enp4s0 -s 192.168.1.0/24 -p tcp --dport 445 -j nixos-fw-accept 2>/dev/null || true
    '';
  };
}
