# Repository conventions

- Group system configurations under `hosts/<platform>/`; keep per-user Home Manager configurations under `home/`.
- Keep shared defaults in `modules/<platform>/base.nix`. Import optional modules explicitly from host or home configurations; do not recursively auto-import modules.
- Do not add a profiles layer unless shared machine roles make it necessary.
- Preserve pinned inputs and existing `stateVersion` values during layout refactors.

# Verification

- Check changed Nix files with `nix fmt -- --check <paths>`.
- Evaluate Darwin outputs with `nix eval --raw .#darwinConfigurations.<host>.system.drvPath`.
- Build Home Manager without activation or replacing `result`: `nix build --no-link --no-write-lock-file '.#homeConfigurations."oliver@onigiri".activationPackage' '.#homeConfigurations."oliver@tempura".activationPackage'`.
- For layout-only changes, compare derivation paths before and after. Darwin configurations with Nix enabled include the repository's own source in the Nix registry, so source-only changes can alter their derivations.
- Darwin hosts that enable Homebrew must set `system.primaryUser`.
- NixOS hosts use integrated Home Manager; their home configurations are activated with the system.
- Keep hardware detection and Disko together in `hardware/<host>.nix`. Use `sudo nixos-generate-config --no-filesystems --show-hardware-config` on the target to refresh detection, preserving the handwritten disk layout.
- Disko manages only ochazuke's NVMe OS disk. Never add the existing `zfs78` HDD pool to its destructive layout. Its generated script recursively unmounts `/mnt`; finish and verify any migration using that mount tree, then cleanly export the pool before running it.
- Build NixOS on an x86_64 Linux machine with `nix build --no-link --no-write-lock-file .#nixosConfigurations.ochazuke.config.system.build.toplevel`; evaluation alone also works on macOS.
- Keep ad-hoc verification scripts outside the repository; do not commit tests unless requested.
