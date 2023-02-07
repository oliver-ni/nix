{ lib, config, pkgs, ... }:

with pkgs.vimUtils;
let
  lc = plugin: config: {
    plugin = plugin;
    type = "lua";
    config = config;
  };
  kubectl-aliases = pkgs.fetchFromGitHub {
    owner = "ahmetb";
    repo = "kubectl-aliases";
    rev = "b2ee5dbd3d03717a596d69ee3f6dc6de8b140128";
    sha256 = "TCk26Wdo35uKyTjcpFLHl5StQOOmOXHuMq4L13EPp0U=";
  };
in
{
  home = {
    username = "oliver";
    homeDirectory = "/Users/oliver";
    stateVersion = "22.11";

    packages = with pkgs; [
      kubectl
    ];
  };

  programs.home-manager.enable = true;

  programs.zsh = {
    enable = true;
    prezto = {
      enable = true;
      prompt.theme = "powerlevel10k";
    };
    plugins = [
      {
        name = "powerlevel10k-config";
        src = lib.cleanSource ./configs/powerlevel10k;
        file = ".p10k.zsh";
      }
      {
        name = "kubectl-aliases";
        src = kubectl-aliases;
        file = ".kubectl_aliases";
      }
    ];
    shellAliases = {
      python = "python3";
      pip = "pip3";
      flushdns = "sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder";
      gensec = "openssl rand -base64 8 | md5 | head -c32";
      "$" = "";
    };
  };

  programs.neovim = {
    enable = true;
    viAlias = true;
    vimAlias = true;

    extraLuaConfig = ''
      vim.g.loaded_netrw = 1
      vim.g.loaded_netrwPlugin = 1
      vim.opt.termguicolors = true
      vim.opt.number = true
      vim.opt.smartindent = true
      vim.opt.expandtab = true
    '';

    plugins = with pkgs.vimPlugins; [
      # UI
      nvim-web-devicons
      telescope-nvim
      indent-blankline-nvim
      (lc nvim-tree-lua ''
        require('nvim-tree').setup()
        local function open_nvim_tree(data)
          if vim.fn.isdirectory(data.file) == 1 then
            vim.cmd.cd(data.file)
          end
          require("nvim-tree.api").tree.open()
        end
        vim.api.nvim_create_autocmd({ "VimEnter" }, { callback = open_nvim_tree })
      '')
      (lc barbar-nvim "require('bufferline').setup()")
      (lc lualine-nvim "require('lualine').setup()")
      (lc catppuccin-nvim "vim.cmd('colorscheme catppuccin-latte')")

      # Code Helpers
      nvim-treesitter
      (lc guess-indent-nvim "require('guess-indent').setup {}")
      (lc comment-nvim "require('Comment').setup()")
      (lc nvim-lspconfig ''
        require('lspconfig').rnix.setup {}
        require('lspconfig').pyright.setup {}
      '')

      # Language Support
      vim-nix

      # Misc
      presence-nvim
      # vim-wakatime
    ];

    extraPackages = with pkgs; [
      ripgrep
      fd
      rnix-lsp
      nodePackages.pyright
    ];
  };
}

