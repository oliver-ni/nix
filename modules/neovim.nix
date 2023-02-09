
{ pkgs, ... }:

with pkgs.vimUtils;
let
  lc = plugin: config: {
    plugin = plugin;
    type = "lua";
    config = config;
  };
in
{
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
            require("nvim-tree.api").tree.open()
          end
        end
        vim.api.nvim_create_autocmd({ "VimEnter" }, { callback = open_nvim_tree })
      '')
      (lc barbar-nvim "require('bufferline').setup()")
      (lc lualine-nvim "require('lualine').setup()")
      (lc catppuccin-nvim "vim.cmd('colorscheme catppuccin-latte')")
      (lc toggleterm-nvim "require('toggleterm').setup { open_mapping = [[<C-`>]] }")

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

