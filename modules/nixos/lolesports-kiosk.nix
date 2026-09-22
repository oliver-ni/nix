{ config, pkgs, ... }:

let
  pickStream = pkgs.writers.writePython3Bin "lolesports-pick-stream" { flakeIgnore = [ "E501" ]; } (
    builtins.readFile ./lolesports-kiosk/pick-stream.py
  );

  idleImage = pkgs.runCommand "kiosk-idle.png" { nativeBuildInputs = [ pkgs.imagemagick ]; } ''
    magick -size 3840x2160 xc:'#0b0d12' \
      -fill '#3a3f4b' -font DejaVu-Sans -pointsize 96 -gravity center \
      -annotate +0+0 'no matches live' "$out"
  '';

  mpvHome = pkgs.writeTextDir "mpv.conf" ''
    fullscreen=yes
    gpu-context=wayland
    hwdec=nvdec
    osc=no
    input-default-bindings=no
    osd-level=0
  '';

  kiosk = pkgs.writeShellApplication {
    name = "lolesports-kiosk";
    runtimeInputs = [
      pkgs.streamlink
      pkgs.mpv
      pickStream
    ];
    runtimeEnv = {
      PICK_STREAM = "${pickStream}/bin/lolesports-pick-stream";
      IDLE_IMAGE = idleImage;
      MPV_HOME = mpvHome;
    };
    text = builtins.readFile ./lolesports-kiosk/kiosk.sh;
  };
in
{
  # The GTX 1060's HDMI output shows whichever LoL Esports match is live,
  # picked by league tier and English commentary. Nothing else uses tty1.
  users.users.kiosk = {
    isSystemUser = true;
    group = "kiosk";
    extraGroups = [
      "video"
      "audio"
      "input"
    ];
    home = "/var/lib/kiosk";
    createHome = true;
  };
  users.groups.kiosk = { };

  # The cage module replaces getty on tty1 and hooks itself into the graphical
  # target, which a headless server never reaches; start it from multi-user.
  services.cage = {
    enable = true;
    user = "kiosk";
    program = "${kiosk}/bin/lolesports-kiosk";
    extraArguments = [ "-s" ];
    environment.WLR_NO_HARDWARE_CURSORS = "1";
    restartIfChanged = true;
  };
  systemd.services.cage-tty1 = {
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Restart = "always";
      RestartSec = 5;
      TimeoutStopSec = 15;
    };
  };
  # cage only Conflicts= with getty@tty1; if getty is still wanted it wins the
  # race on activation and stops cage. Keep the console on tty2+.
  systemd.services."getty@tty1".enable = false;

  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };
}
