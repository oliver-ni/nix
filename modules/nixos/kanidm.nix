{
  config,
  lib,
  pkgs,
  ...
}:

let
  domain = "ochazuke.org";
  origin = "https://accounts.${domain}";
  port = 8443;
  tlsDir = "/var/lib/kanidm/tls";

  # Every helper talks to Kanidm on loopback as idm_admin; `read` is how it
  # gets at the password file (plain `cat` as root, `sudo cat` for a person).
  loginAsIdmAdmin = read: ''
    export KANIDM_NAME=idm_admin
    export KANIDM_URL=https://localhost:${toString port}
    export KANIDM_ACCEPT_INVALID_CERTS=true
    KANIDM_PASSWORD=$(${read} ${config.age.secrets.kanidm-idm-admin-password.path})
    export KANIDM_PASSWORD
    kanidm login
  '';

  # kanidm-provision cannot set account policy, so it is applied with the CLI
  # after provisioning. The strictest policy across a person's groups wins and
  # idm_all_persons defaults to MFA, so that is where password-only logins have
  # to be allowed; passkeys and TOTP stay optional.
  accountPolicy = pkgs.writeShellApplication {
    name = "kanidm-account-policy";
    runtimeInputs = [ config.services.kanidm.package ];
    text = ''
      export HOME
      HOME=$(mktemp -d)
      trap 'rm -rf "$HOME"' EXIT
      ${loginAsIdmAdmin "cat"}
      kanidm group account-policy credential-type-minimum idm_all_persons any
    '';
  };

  # Creates a person, puts them in the group the OAuth2 clients admit, and
  # prints a one-time link where they set their own password or passkey. Komga
  # matches people by mail, so give the real address when it is known.
  invite = pkgs.writeShellApplication {
    name = "ochazuke-invite";
    runtimeInputs = [ config.services.kanidm.package ];
    text = ''
      if [ $# -lt 1 ] || [ $# -gt 3 ]; then
        echo "usage: ochazuke-invite <username> [display name] [email]" >&2
        exit 64
      fi
      name=$1
      display=''${2:-$1}
      mail=''${3:-$1@${domain}}

      ${loginAsIdmAdmin "sudo cat"}
      kanidm person create "$name" "$display"
      kanidm person update "$name" --mail "$mail"
      kanidm group add-members ochazuke_users "$name"
      kanidm person credential create-reset-token "$name" --ttl 86400
    '';
  };
in
{
  age.secrets = {
    kanidm-admin-password = {
      file = ../../secrets/kanidm-admin-password.age;
      owner = "kanidm";
    };
    kanidm-idm-admin-password = {
      file = ../../secrets/kanidm-idm-admin-password.age;
      owner = "kanidm";
    };
    kanidm-oauth2-jellyfin = {
      file = ../../secrets/kanidm-oauth2-jellyfin.age;
      owner = "kanidm";
    };
  };

  environment.systemPackages = [ invite ];

  services.kanidm = {
    package = pkgs.kanidm_1_11.withSecretProvisioning;

    # Kanidm insists on terminating TLS itself, so it gets a self-signed
    # certificate on loopback (kanidm-tls below) and Caddy fronts it at
    # accounts.${domain} with the real one.
    server = {
      enable = true;
      settings = {
        inherit domain origin;
        bindaddress = "127.0.0.1:${toString port}";
        tls_chain = "${tlsDir}/chain.pem";
        tls_key = "${tlsDir}/key.pem";
        http_client_address_info.x-forward-for = [ "127.0.0.1" ];
        online_backup.versions = 7;
      };
    };

    # The `kanidm` CLI on the box, through Caddy like everyone else.
    client = {
      enable = true;
      settings.uri = origin;
    };

    provision = {
      enable = true;
      adminPasswordFile = config.age.secrets.kanidm-admin-password.path;
      idmAdminPasswordFile = config.age.secrets.kanidm-idm-admin-password.path;

      # People are not declared here (the repository is public); membership is
      # managed with ochazuke-invite and the CLI, so the groups are declared
      # only for the clients below to refer to.
      groups = {
        ochazuke_users.overwriteMembers = false;
        ochazuke_admins.overwriteMembers = false;
      };

      systems.oauth2 = {
        jellyfin = {
          displayName = "Jellyfin";
          originUrl = [
            "https://jellyfin.${domain}/sso/OID/redirect/ochazuke"
            "https://${domain}/sso/OID/redirect/ochazuke"
          ];
          originLanding = "https://${domain}";
          basicSecretFile = config.age.secrets.kanidm-oauth2-jellyfin.path;

          # The SSO plugin links Kanidm accounts to Jellyfin users by
          # preferred_username, so it must be the bare name rather than the
          # name@domain SPN.
          preferShortUsername = true;
          scopeMaps.ochazuke_users = [
            "openid"
            "profile"
            "email"
          ];
          claimMaps.jellyfin_roles.valuesByGroup.ochazuke_admins = [ "admin" ];
        };

        komga = {
          displayName = "Manga";
          originUrl = "https://manga.${domain}/login/oauth2/code/ochazuke";
          originLanding = "https://manga.${domain}";

          # Spring only does PKCE for public clients, and only validates RS256
          # ID tokens.
          public = true;
          enableLegacyCrypto = true;
          preferShortUsername = true;
          scopeMaps.ochazuke_admins = [
            "openid"
            "profile"
            "email"
          ];
        };
      };
    };
  };

  systemd.services.kanidm.serviceConfig.ExecStartPost = lib.mkAfter [ (lib.getExe accountPolicy) ];

  systemd.services.kanidm-tls = {
    before = [ "kanidm.service" ];
    requiredBy = [ "kanidm.service" ];

    serviceConfig = {
      Type = "oneshot";
      User = "kanidm";
      Group = "kanidm";
      StateDirectory = "kanidm";
      StateDirectoryMode = "0700";
    };

    script = ''
      if [ ! -e ${tlsDir}/key.pem ]; then
        mkdir -p ${tlsDir}
        ${pkgs.openssl}/bin/openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
          -nodes -days 3650 -subj "/CN=accounts.${domain}" \
          -keyout ${tlsDir}/key.pem -out ${tlsDir}/chain.pem
      fi
    '';
  };
}
