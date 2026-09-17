{ lib, pkgs, ... }:

let
  kubectl-aliases = pkgs.fetchFromGitHub {
    owner = "ahmetb";
    repo = "kubectl-aliases";
    rev = "b2ee5dbd3d03717a596d69ee3f6dc6de8b140128";
    sha256 = "TCk26Wdo35uKyTjcpFLHl5StQOOmOXHuMq4L13EPp0U=";
  };
  jj-aliases = pkgs.fetchFromGitHub {
    owner = "oliver-ni";
    repo = "jj-aliases";
    rev = "a995f195b18dc8b1bc14ed01ef58c2df2ab6ed5d";
    sha256 = "7vLzuE2Po38Ue/0YsdTag/3CySPx8nXTF9aG0zzozGI=";
  };
in
{
  programs.zsh = {
    enable = true;
    completionInit = "autoload -U compinit && compinit -C";

    sessionVariables = {
      EDITOR = "vim";
      VISUAL = "vim";
    };

    plugins = [
      { name = "powerlevel10k"; src = pkgs.zsh-powerlevel10k; file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme"; }
      { name = "powerlevel10k-config"; src = lib.cleanSource ./zsh; file = "p10k.zsh"; }
      { name = "gcl"; src = lib.cleanSource ./zsh; file = "gcl.zsh"; }
      { name = "tmp"; src = lib.cleanSource ./zsh; file = "tmp.zsh"; }
      { name = "kubectl-aliases"; src = kubectl-aliases; file = ".kubectl_aliases"; }
      { name = "jj-aliases"; src = jj-aliases; file = ".jj_aliases"; }
    ];

    initExtraFirst = ''
      # >>>> BEGIN MANAGED DEVIN BLOCK >>>>
      # Add ~/.local/bin to PATH for devin
      if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        export PATH="$HOME/.local/bin:$PATH"
      fi
      if [ -x "/Users/oliver/.local/bin/devin" ]; then
        eval "$("/Users/oliver/.local/bin/devin" shell init zsh --stage pre)"
      fi
      # <<<< END MANAGED DEVIN BLOCK <<<<

      # p10k instant prompt — must be before anything that produces output
      if [[ -r "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh" ]]; then
        source "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh"
      fi
    '';

    initExtra = ''
      export PATH="$PATH:$HOME/.local/bin"
      export PATH="$PATH:$HOME/.cargo/bin"
      export PATH="''${KREW_ROOT:-$HOME/.krew}/bin:$PATH"

      bindkey "^U" backward-kill-line

      autoload -U up-line-or-beginning-search
      autoload -U down-line-or-beginning-search
      zle -N up-line-or-beginning-search
      zle -N down-line-or-beginning-search
      bindkey "^[[A" up-line-or-beginning-search
      bindkey "^[[B" down-line-or-beginning-search

      [ "$TERM" = "xterm-kitty" ] && alias ssh="kitty +kitten ssh"
      eval "$(/opt/homebrew/bin/brew shellenv)"

      # >>>> BEGIN MANAGED DEVIN BLOCK >>>>
      if [ -x "/Users/oliver/.local/bin/devin" ]; then
        eval "$("/Users/oliver/.local/bin/devin" shell init zsh --stage post)"
      fi
      # <<<< END MANAGED DEVIN BLOCK <<<<
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
