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
      {
        name = "powerlevel10k";
        src = pkgs.zsh-powerlevel10k;
        file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
      }

      {
        name = "powerlevel10k-config";
        src = lib.cleanSource ./zsh;
        file = "p10k.zsh";
      }

      {
        name = "gcl";
        src = lib.cleanSource ./zsh;
        file = "gcl.zsh";
      }

      {
        name = "tmp";
        src = lib.cleanSource ./zsh;
        file = "tmp.zsh";
      }

      {
        name = "kubectl-aliases";
        src = kubectl-aliases;
        file = ".kubectl_aliases";
      }

      {
        name = "jj-aliases";
        src = jj-aliases;
        file = ".jj_aliases";
      }
    ];

    initContent = lib.mkMerge [
      (lib.mkBefore ''
        # p10k instant prompt — must be before anything that produces output
        if [[ -r "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh" ]]; then
          source "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh"
        fi

        # >>>> BEGIN MANAGED DEVIN BLOCK >>>>
        # Add ~/.local/bin to PATH for devin
        typeset -U path
        path=("''${KREW_ROOT:-$HOME/.krew}/bin" "$HOME/.local/bin" "''${path[@]}" "$HOME/.cargo/bin")
        if [ -x "$HOME/.local/bin/devin" ]; then
          eval "$("$HOME/.local/bin/devin" shell init zsh --stage pre)"
        fi
        # <<<< END MANAGED DEVIN BLOCK <<<<
      '')
      ''
        bindkey "^U" backward-kill-line

        autoload -U up-line-or-beginning-search
        autoload -U down-line-or-beginning-search
        zle -N up-line-or-beginning-search
        zle -N down-line-or-beginning-search
        bindkey "^[[A" up-line-or-beginning-search
        bindkey "^[[B" down-line-or-beginning-search

        if [[ "$TERM" = "xterm-kitty" ]] && (( $+commands[kitty] )); then
          alias ssh="kitty +kitten ssh"
        fi
        ${lib.optionalString pkgs.stdenv.isDarwin ''
          if [[ -x /opt/homebrew/bin/brew ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
          fi
        ''}

        # >>>> BEGIN MANAGED DEVIN BLOCK >>>>
        if [ -x "$HOME/.local/bin/devin" ]; then
          eval "$("$HOME/.local/bin/devin" shell init zsh --stage post)"
        fi
        # <<<< END MANAGED DEVIN BLOCK <<<<
      ''
    ];

    shellAliases = {
      python = "python3";
      gensec = "${lib.getExe pkgs.openssl} rand -hex 16";
      dotenv = "set -o allexport; source .env; set +o allexport";
      "$" = "";
    }
    // lib.optionalAttrs pkgs.stdenv.isDarwin {
      flushdns = "sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder";
    };
  };
}
