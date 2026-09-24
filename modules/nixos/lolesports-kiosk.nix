{
  config,
  lib,
  pkgs,
  ...
}:

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
    # logind gives system users a session without a user manager; lingering
    # runs user@kiosk anyway so pipewire's user units exist and
    # switch-to-configuration's per-user activation has a bus to talk to.
    linger = true;
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
  # Without a display manager the getty module makes getty.target want
  # autovt@tty1, which every switch-to-configuration starts; cage's Conflicts=
  # then stops cage instead. Drop the want (as display managers do) and keep
  # the console on tty2+.
  systemd.targets.getty.wants = lib.mkForce [ ];

  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };
}
