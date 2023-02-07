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
      vim.opt.completeopt = "menu,menuone,noselect"
    '';

    plugins = with pkgs.vimPlugins; [
      # UI
      nvim-web-devicons
      telescope-nvim
      indent-blankline-nvim
      (lc nvim-tree-lua ''
        require('nvim-tree').setup {
          filters = {
            custom = { '^\\.git' }
          }
        }
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
      ultisnips
      cmp-git
      cmp-nvim-lsp
      (lc nvim-cmp ''
        local cmp = require('cmp')
        cmp.setup {
          snippet = {
            expand = function(args)
              vim.fn['UltiSnips#Anon'](args.body)
            end
          },
          mapping = cmp.mapping.preset.insert({
            ['<C-b>'] = cmp.mapping.scroll_docs(-4),
            ['<C-f>'] = cmp.mapping.scroll_docs(4),
            ['<C-Space>'] = cmp.mapping.complete(),
            ['<C-e>'] = cmp.mapping.abort(),
            ['<CR>'] = cmp.mapping.confirm({ select = true }),
          }),
          sources = cmp.config.sources {
            { name = 'nvim_lsp' },
            { name = 'ultisnips' }
          }, {
            { name = 'buffer' }
          }
        }

        cmp.setup.filetype('gitcommit', {
          sources = cmp.config.sources({
            { name = 'git' },
          }, {
            { name = 'buffer' },
          })
        })

        cmp.setup.cmdline({ '/', '?' }, {
          mapping = cmp.mapping.preset.cmdline(),
          sources = {
            { name = 'buffer' }
          }
        })

        cmp.setup.cmdline(':', {
          mapping = cmp.mapping.preset.cmdline(),
          sources = cmp.config.sources({
            { name = 'path' }
          }, {
            { name = 'cmdline' }
          })
        })

        require('cmp_git').setup()
      '')
      (lc gitsigns-nvim "require('gitsigns').setup()")
      (lc guess-indent-nvim "require('guess-indent').setup {}")
      (lc comment-nvim "require('Comment').setup()")
      (lc nvim-lspconfig ''
        local capabilities = require('cmp_nvim_lsp').default_capabilities()
        require('lspconfig').rnix.setup { capabilities = capabilities }
        require('lspconfig').pyright.setup { capabilities = capabilities }
        require('lspconfig').tsserver.setup { capabilities = capabilities }
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
      nodePackages.typescript-language-server
    ];
  };
}

