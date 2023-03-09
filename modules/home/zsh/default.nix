{ lib, pkgs, ... }:

let
  kubectl-aliases = pkgs.fetchFromGitHub {
    owner = "ahmetb";
    repo = "kubectl-aliases";
    rev = "b2ee5dbd3d03717a596d69ee3f6dc6de8b140128";
    sha256 = "TCk26Wdo35uKyTjcpFLHl5StQOOmOXHuMq4L13EPp0U=";
  };
in
{
  programs.zsh = {
    enable = true;

    plugins = [
      {
        name = "powerlevel10k";
        src = pkgs.zsh-powerlevel10k;
        file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
      }
      {
        name = "powerlevel10k-config";
        src = lib.cleanSource ./.;
        file = ".p10k.zsh";
      }
      {
        name = "kubectl-aliases";
        src = kubectl-aliases;
        file = ".kubectl_aliases";
      }
    ];

    initExtra = ''
      bindkey "^U" backward-kill-line

      autoload -U up-line-or-beginning-search
      autoload -U down-line-or-beginning-search
      zle -N up-line-or-beginning-search
      zle -N down-line-or-beginning-search
      bindkey "^[[A" up-line-or-beginning-search
      bindkey "^[[B" down-line-or-beginning-search

      eval "$(/opt/homebrew/bin/brew shellenv)"
    '';

    shellAliases = {
      python = "python3";
      flushdns = "sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder";
      gensec = "openssl rand -base64 8 | md5 | head -c32";
      dotenv = "set -o allexport; source .env; set +o allexport";
      "$" = "";
    };
  };
}
