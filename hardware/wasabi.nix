{
  config,
  lib,
  modulesPath,
  ...
}:

{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "ahci"
    "usbhid"
    "usb_storage"
    "sd_mod"
  ];
  boot.kernelModules = [ "kvm-amd" ];

  disko.devices = {
    disk.main = {
      device = "/dev/disk/by-id/nvme-Samsung_SSD_990_PRO_1TB_S73VNJ0WB00164F";
      type = "disk";

      content = {
        type = "gpt";

        partitions = {
          ESP = {
            size = "1G";
            type = "EF00";

            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };

          zfs = {
            size = "100%";

            content = {
              type = "zfs";
              pool = "nixos";
            };
          };
        };
      };
    };

    zpool.nixos = {
      type = "zpool";

      options = {
        ashift = "12";
        cachefile = "none";
      };

      rootFsOptions = {
        acltype = "posix";
        atime = "off";
        compression = "zstd";
        mountpoint = "legacy";
        xattr = "sa";
      };

      datasets = {
        root = {
          type = "zfs_fs";
          mountpoint = "/";
          options.mountpoint = "legacy";
        };

        nix = {
          type = "zfs_fs";
          mountpoint = "/nix";
          options.mountpoint = "legacy";
        };

        var = {
          type = "zfs_fs";
          mountpoint = "/var";
          options.mountpoint = "legacy";
        };

        home = {
          type = "zfs_fs";
          mountpoint = "/home";
          options.mountpoint = "legacy";
        };

        # Raw image of the Pump It Up Phoenix SSD; the only copy.
        piu-backup = {
          type = "zfs_fs";
          mountpoint = "/mnt/bk";
          options.mountpoint = "legacy";
        };

        piu-work = {
          type = "zfs_fs";
          mountpoint = "/mnt/piu-work";
          options.mountpoint = "legacy";
        };
      };
    };
  };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
