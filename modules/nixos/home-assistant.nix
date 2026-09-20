{ ... }:

{
  services.home-assistant = {
    enable = true;
    config = null;
    extraComponents = [
      "aranet"
      "default_config"
      "met"
    ];
  };
}
