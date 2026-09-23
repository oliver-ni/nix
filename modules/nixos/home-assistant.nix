{ ... }:

{
  services.home-assistant = {
    enable = true;
    extraComponents = [
      "aranet"
      "default_config"
      "met"
    ];

    # Nix owns configuration.yaml; automations, scenes, and scripts stay in
    # their UI-managed include files. Caddy proxies it at
    # https://ha.ochazuke.org over the tailnet. Note HA 2026.x reads http
    # settings from .storage/http once `yaml_migration_done` is set there and
    # ignores this block; the same two keys were added to that file by hand.
    config = {
      default_config = { };
      frontend.themes = "!include_dir_merge_named themes";
      automation = "!include automations.yaml";
      script = "!include scripts.yaml";
      scene = "!include scenes.yaml";
      http = {
        use_x_forwarded_for = true;
        trusted_proxies = [
          "127.0.0.1"
          "::1"
        ];
      };
    };
  };
}
