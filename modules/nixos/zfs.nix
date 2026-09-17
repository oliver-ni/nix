{ ... }:

{
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.forceImportRoot = false;

  services.zfs.autoScrub.enable = true;

  services.smartd = {
    enable = true;
    defaults.monitored = "-a -s (S/../.././02|L/../../7/04)";
  };
}
