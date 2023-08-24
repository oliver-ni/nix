{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    fzf
  ];

  programs.kitty = {
    enable = true;

    extraConfig = ''
      enabled_layouts             splits:split_axis=vertical
      scrollback_lines            1000000000
      tab_bar_edge                top
      tab_bar_margin_height       0.0 5.0
      tab_bar_style               powerline
      tab_bar_min_tabs            1
      tab_powerline_style         slanted
      tab_title_template          {(p := tab.active_oldest_wd.replace("${config.home.homeDirectory}", "~").split("/")) and "/".join([x[:1] for x in p[:-2]] + p[-2:])} • {tab.active_exe}{f" [{num_windows}]" if num_windows > 1 else ""}
    '';

    font.name = "PragmataPro Liga";
    font.size = 17;
    theme = "Catppuccin-Latte";

    keybindings = {
      "cmd+w" = "close_window";
      "cmd+d" = "launch --location=vsplit --cwd=current";
      "cmd+shift+d" = "launch --location=hsplit --cwd=current";
      "cmd+[" = "previous_window";
      "cmd+]" = "next_window";

      "cmd+backspace" = "send_text all \\x15";
      "cmd+delete" = "send_text all \\x0b";
      "cmd+left" = "send_text all \\x01";
      "cmd+right" = "send_text all \\x05";

      "opt+backspace" = "send_text all \\x1b\\x08";
      "opt+delete" = "send_text all \\x1b\\x64";
      "opt+left" = "send_text all \\x1b\\x62";
      "opt+right" = "send_text all \\x1b\\x66";

      "cmd+f" = "launch --type=overlay --stdin-source=@screen_scrollback fzf --no-sort -i";
      "cmd+z" = "send_text all \\x1f";
    };
  };
}
