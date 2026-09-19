{ config, pkgs, ... }:

let
  package = pkgs.stdenv.mkDerivation {
    pname = "jfa-go";
    version = "0.6.0";

    src = pkgs.fetchurl {
      url = "https://github.com/hrfee/jfa-go/releases/download/v0.6.0/jfa-go_0.6.0_Linux_x86_64.zip";
      hash = "sha256:15e7502380169457ec6c3f777b0e1bd6b7e65b01c133b2f4c1fb29a64cbbc591";
    };

    sourceRoot = ".";
    nativeBuildInputs = [
      pkgs.unzip
      pkgs.autoPatchelfHook
    ];
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      install -Dm755 jfa-go "$out/bin/jfa-go"
      runHook postInstall
    '';
  };
in
{
  age.secrets.jfa-go-config.file = ../../secrets/jfa-go-config.age;

  systemd.services.jfa-go = {
    description = "Jellyfin invitations and account management";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target"
      "jellyfin.service"
    ];
    wants = [ "network-online.target" ];

    preStart = ''
      if [ ! -e /var/lib/jfa-go/config.ini ]; then
        install -m600 "$CREDENTIALS_DIRECTORY/config.ini" /var/lib/jfa-go/config.ini
      fi
    '';

    serviceConfig = {
      ExecStart = "${package}/bin/jfa-go -data /var/lib/jfa-go -config /var/lib/jfa-go/config.ini";
      DynamicUser = true;
      StateDirectory = "jfa-go";
      StateDirectoryMode = "0700";
      WorkingDirectory = "/var/lib/jfa-go";
      LoadCredential = "config.ini:${config.age.secrets.jfa-go-config.path}";
      UMask = "0077";
      Restart = "on-failure";
      RestartSec = 5;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictSUIDSGID = true;
      RestrictAddressFamilies = [
        "AF_UNIX"
        "AF_INET"
        "AF_INET6"
      ];
    };
  };
}
