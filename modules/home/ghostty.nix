{ config, pkgs, ... }:

{
  xdg.configFile."ghostty/config".text = ''
    theme = dark:Catppuccin Frappe,light:Catppuccin Latte
    
    font-family = PragmataPro Mono Liga
    font-size = 17
    font-thicken = false
    
    scrollback-limit = 1000000000
    
    keybind = cmd+backspace=text:\x15
    keybind = cmd+left=text:\x01
    keybind = cmd+right=text:\x05
    keybind = opt+backspace=text:\x1b\x08
    keybind = opt+left=text:\x1b\x62
    keybind = opt+right=text:\x1b\x66
    
    window-padding-x = 4
    window-padding-y = 4
    window-padding-balance = true
  '';
}
