# Repository conventions

- Group system configurations under `hosts/<platform>/`; keep per-user Home Manager configurations under `home/`.
- Keep shared defaults in `modules/<platform>/base.nix`. Import optional modules explicitly from host or home configurations; do not recursively auto-import modules.
- Do not add a profiles layer unless shared machine roles make it necessary.
- Preserve pinned inputs and existing `stateVersion` values during layout refactors.
- Collapse single-child attribute nesting into dotted paths. Keep attribute sets where they group multiple settings.
- Use blank lines between logical sections and sibling blocks; keep closely related scalar settings together.
- Omit settings that merely repeat defaults unless they document an important hardware or safety requirement; check the pinned module defaults before removing them.
- The Macs use Determinate Nix. Keep `nix.enable = false`, but manage `/etc/nix/registry.json` through `environment.etc`, using the `nix.registry` declarations. Do not let nix-darwin replace Determinate's daemon or `nix.conf`.

# Verification

- Use the official `nixfmt` formatter via `nix fmt` (`nixfmt-tree` handles the repository). Check formatting with `nix fmt -- --fail-on-change`.
- Evaluate Darwin outputs with `nix eval --raw .#darwinConfigurations.<host>.system.drvPath`.
- Build Home Manager without activation or replacing `result`: `nix build --no-link --no-write-lock-file '.#homeConfigurations."oliver@onigiri".activationPackage' '.#homeConfigurations."oliver@tempura".activationPackage'`.
- For layout-only changes, compare derivation paths before and after. Configurations that register `self` include the repository's source in the Nix registry, so source-only changes can alter their derivations.
- Darwin hosts that enable Homebrew must set `system.primaryUser`.
- NixOS hosts use integrated Home Manager; their home configurations are activated with the system.
- Keep hardware detection and Disko together in `hardware/<host>.nix`. Use `sudo nixos-generate-config --no-filesystems --show-hardware-config` on the target to refresh detection, preserving the handwritten disk layout.
- Disko manages only ochazuke's NVMe OS disk and its `nixos` root pool (`root`, `nix`, `var`, and `home` datasets). Never add the existing `zfs78` HDD pool to its destructive layout. Its generated script recursively unmounts `/mnt`; finish and verify any migration using that mount tree, then cleanly export the pool before running it.
- Build NixOS on an x86_64 Linux machine with `nix build --no-link --no-write-lock-file .#nixosConfigurations.ochazuke.config.system.build.toplevel`; evaluation alone also works on macOS.
- Keep ad-hoc verification scripts outside the repository; do not commit tests unless requested.
- jfa-go administration uses `https://admin.accounts.ochazuke.org` over Tailscale (DNS-only A record to `100.68.129.57`). HTTPS and this subdomain preserve its secure login cookie scoped to `accounts.ochazuke.org`. The public `accounts.ochazuke.org` exposes only invitation pages, their assets, and signup/CAPTCHA endpoints; verify public admin routes return 404 when changing its proxy rules.
- jfa-go seeds its mutable `/var/lib/jfa-go/config.ini` from the agenix credential only when absent. Back up its state directory along with Jellyfin; changing the encrypted seed does not update existing runtime settings.
- Jellyfin uses Abyss from `modules/nixos/jellyfin-theme.nix`; keep SleekFin disabled in Jellyfin's plugin manager to avoid overlapping themes. Existing installations need `@import url("ui/abyss.css");` in branding (POST `/System/Configuration/Branding`), since the module's tmpfiles rule only seeds missing branding.
