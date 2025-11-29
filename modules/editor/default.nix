{
  config,
  pkgs,
  lib,
  ...
}:
let
  # https://gist.github.com/nat-418/d76586da7a5d113ab90578ed56069509
  vimPluginFromGitHubRef =
    ref: repo:
    pkgs.vimUtils.buildVimPlugin {
      pname = "${lib.strings.sanitizeDerivationName repo}";
      version = ref;
      src = builtins.fetchGit {
        url = "https://github.com/${repo}.git";
        inherit ref;
      };
    };
  vimPluginFromGitHubRevWithDeps =
    rev: repo: deps:
    pkgs.vimUtils.buildVimPlugin {
      pname = "${lib.strings.sanitizeDerivationName repo}";
      version = rev;
      dependencies = deps;
      src = builtins.fetchGit {
        url = "https://github.com/${repo}.git";
        inherit rev;
      };
    };
  vimPluginFromGitHubRev = rev: repo: vimPluginFromGitHubRevWithDeps rev repo [ ];

  vimTemp = pkgs.writeShellApplication {
    name = "vt";
    text = ''
      tmpfile="$(mktemp)"
      rm_tmpfile() {
        test -f "$tmpfile" && rm -f "$tmpfile"
      }
      trap rm_tmpfile EXIT
      vim "$tmpfile" -c "set filetype=''${1:-markdown}"
    '';
  };
  neovimExtraLuaConfigForAllEnvironment = ''
    --[[
      Common settings.
    --]]
    -- disable editorconfig: cannot control the range of format.
    vim.g.editorconfig = false
    --[[
      keymap rules:
      Ctrl-Shift to Alt
    --]]
    -- general settings
    local function map(mode, lhs, rhs, opts)
      local options = {noremap = true}
      if opts then options = vim.tbl_extend('force', options, opts) end
      -- vim.api.nvim_set_keymap(mode, lhs, rhs, options)
      vim.keymap.set(mode, lhs, rhs, options)
    end
    local api = vim.api
    local opt = vim.opt
    --[[
      Common plugins that can use all environments
    --]]
    -- hop-nvim
    local hop = require('hop')
    local hint = require('hop.hint')
    hop.setup()
    map("n", "f", function() hop.hint_char1({ direction = hint.HintDirection.AFTER_CURSOR, current_line_only = true }) end, { remap = true })
    map("n", "F", function() hop.hint_char1({ direction = hint.HintDirection.BEFORE_CURSOR, current_line_only = true }) end, { remap = true })
    map("n", "<Leader><Leader>k", function() hop.hint_lines_skip_whitespace({
      direction = hint.HintDirection.BEFORE_CURSOR}) end, { desc = "Hop above" })
    map("n", "<Leader><Leader>j", function() hop.hint_lines_skip_whitespace({
      direction = hint.HintDirection.AFTER_CURSOR}) end, { desc = "Hop below" })
    -- comment-nvim
    require('Comment').setup()
    --   Ctrl+/ to comment-out line. _ as slash
    map("n", "<C-_>", require('Comment.api').toggle.linewise.current, { noremap = true, silent = true })
    map('v', '<C-_>', '<ESC><CMD>lua require("Comment.api").toggle.linewise(vim.fn.visualmode())<CR>', { noremap = true, silent = true })
    -- wildfire-nvim
    require("wildfire").setup()
    -- nvim-surround
    require("nvim-surround").setup()
    -- nvim-spider for smartword
    require("spider").setup {
      subwordMovement = false,
    }
    -- treesj
    require('treesj').setup({
      use_default_keymaps = tree
    })
    map({ "n", "o", "x" }, "w", "<cmd>lua require('spider').motion('w')<CR>")
    map({ "n", "o", "x" }, "e", "<cmd>lua require('spider').motion('e')<CR>")
    map({ "n", "o", "x" }, "b", "<cmd>lua require('spider').motion('b')<CR>")
  '';

  neovimExtraLuaConfigForNativeOnly = ''
    --[[
      Look and feel plugins only enable on native only
    --]]
    -- colorsheme
    vim.cmd('colorscheme github_dark_dimmed')
    require('github-theme').setup({}) -- github scheme has transparent option, but cannot use because unfocused window cannot be transparent.
    -- transparent-nvim
    require("transparent").setup({})
    vim.g.transparent_enabled = true
    -- lualine-nvim
    require('lualine').setup {
      options = {
        theme = "ayu_dark",
        section_separators = "",
        component_separators = "",
      },
    }
    -- alpha-nvim
    require('alpha').setup(require('alpha.themes.startify').config)
    -- vim-illuminate, but too slow...
    -- require('illuminate').configure({
    --   provider = { -- default includes regex(maybe slow) so define without it
    --     "lsp",
    --     "treesitter",
    --   }
    -- })

    -- noice-nvim
    require("noice").setup({
      --[[
        To resolve conflicts between lsp-signature and noice.
        https://minerva.mamansoft.net/Notes/%F0%9F%93%9DNoice%E3%81%A8lsp_signature.nvim%E3%82%92%E3%82%A4%E3%83%B3%E3%82%B9%E3%83%88%E3%83%BC%E3%83%AB%E3%81%97%E3%81%9F%E7%8A%B6%E6%85%8B%E3%81%A7%E8%B5%B7%E5%8B%95%E3%81%99%E3%82%8B%E3%81%A8overwritten%E3%81%AE%E3%82%A8%E3%83%A9%E3%83%BC%E3%81%AB%E3%81%AA%E3%82%8B
      --]]
      lsp = {
        signature = {
          enabled = false,
        },
      },
    })
    -- fidget-nvim
    require('fidget').setup()
    -- todo-comments-nvim
    require("todo-comments").setup()
    -- nvim-treesitter-context for stick scroll
    require('treesitter-context').setup()

    --[[
      The plugins that uses another window/pane/tab/tmux only enable on native only
    --]]
    -- nvim-spectre
    require('spectre').setup()
    map('n', '<A-f>', '<cmd>lua require("spectre").toggle()<CR>', { desc = "Toggle Spectre" })
    map('n', '<leader>sw', '<cmd>lua require("spectre").open_visual({select_word=true})<CR>', { desc = "Search current word" })
    map('v', '<leader>sw', '<esc><cmd>lua require("spectre").open_visual()<CR>', { desc = "Search current word" })
    map('n', '<leader>sp', '<cmd>lua require("spectre").open_file_search({select_word=true})<CR>', { desc = "Search on current file" })
    -- fzf-lua
    require("fzf-lua").setup()
    map("n", "<C-P>", require('fzf-lua').oldfiles, { desc = "Fzf Files MRU" })
    map("n", "<Leader>fd", require('fzf-lua').files, { desc = "Fzf Files fd" })
    map("n", "<Leader>rg", require('fzf-lua').grep_project, { desc = "Fzf Grep Project" })
    map("n", "<A-p>", "<CMD>lua require('fzf-lua').commands()<CR>", { desc = "Fzf Command", silent = true })
    map('n', "<A-.>", require('fzf-lua').lsp_code_actions, { desc = "Fzf Lsp code actions" })
    map('n', "<A-m>", require('fzf-lua').lsp_workspace_diagnostics, { desc = "Fzf Lsp workspace diagnostic" })
    -- which-key.nvim
    require("which-key").setup({
      plugins = {
        presets = { operators = false },
      },
    })

    --[[
      The plugins that integrates vcs and the other features only enable on native only
    --]]
    -- gitsigns-nvim
    require('gitsigns').setup({
      watch_gitdir = { interval = 1000 }
    })
    -- lazygit-nvim
    map("n", "<Leader>lg", ":LazyGitCurrentFile<CR>", { desc = "Lazygit", silent = true, })

    --[[
      The LSP related plugins only enable on native only
    --]]
    -- hlargs-nvim
    require("hlargs").setup()
    -- lsp_signature-nvim
    require('lsp_signature').setup()

    -- LSP and completions
    local cmp = require('cmp')
    local cmp_exit = function()
      cmp.mapping.close()
      api.nvim_feedkeys(api.nvim_replace_termcodes('<Esc>', true, true, true), 'n', true)
    end

    vim.lsp.inlay_hint.enable = true
    cmp.setup {
      formatting = {
        fields = { cmp.ItemField.Abbr, cmp.ItemField.Menu },
        format = function(entry, item)
          item.menu = ' '
            .. item.kind
            .. ' '
            .. '[' .. (({ nvim_lsp = 'lsp', cmp_git = 'git' })[entry.source.name] or entry.source.name) .. ']'
          return item
        end,
      },
      snippet = {
        expand = function(args)
          require('luasnip').lsp_expand(args.body)
        end,
      },
      mapping = {
        ['<C-p>'] = cmp.mapping.select_prev_item(),
        ['<C-n>'] = cmp.mapping.select_next_item(),
        ['<tab>'] = cmp.mapping.select_next_item(),
        ['<C-space>'] = cmp.mapping.complete(),
        ["<Esc>"] = cmp.mapping({
          -- i = cmp.mapping.abort(),
          -- c = cmp.mapping.close(),
          i = cmp_exit,
          c = cmp_exit,
        }),
        ['<Enter>'] = cmp.mapping.confirm { select = true },
      },
      sources = cmp.config.sources({
        { name = 'nvim_lsp' },
        { name = 'luasnip' },
        { name = 'path' },
        { name = 'buffer' },
        { name = 'spell' },
        { name = 'nvim_lsp_signature_help' },
        { name = 'git' },
        { name = 'rg' },
        { name = 'treesitter' },
      }),
    }

    local lsp_mappings = {
      { 'gD', vim.lsp.buf.declaration },
      { 'gd', vim.lsp.buf.definition },
      { 'gi', vim.lsp.buf.implementation },
      { 'gr', vim.lsp.buf.references },
      { '[d', vim.diagnostic.goto_prev },
      { ']d', vim.diagnostic.goto_next },
      { ' ' , vim.lsp.buf.hover },
      { ' s', vim.lsp.buf.signature_help },
      { ' d', vim.diagnostic.open_float },
      { ' q', vim.diagnostic.setloclist },
      { '\\r', vim.lsp.buf.rename },
      { '\\a', vim.lsp.buf.code_action },
    }
    for i, mapping in pairs(lsp_mappings) do
      map('n', mapping[1], function() mapping[2]() end)
    end
    map('x', '\\a', function() vim.lsp.buf.code_action() end)

    -- https://github.com/neovim/nvim-lspconfig/wiki/Autocompletion
    -- https://github.com/hrsh7th/cmp-nvim-lsp/issues/42#issuecomment-1283825572
    local caps = vim.tbl_deep_extend(
      'force',
      vim.lsp.protocol.make_client_capabilities(),
      require('cmp_nvim_lsp').default_capabilities(),
      -- File watching is disabled by default for neovim.
      -- See: https://github.com/neovim/neovim/pull/22405
      { workspace = { didChangeWatchedFiles = { dynamicRegistration = true } } }
    );

    require('lspconfig').typos_lsp.setup({
      cmd_env = { RUST_LOG = "error" },
      init_options = {
        diagnosticSeverity = "Warning"
      }
    })

    --[[
      nvim-treesitter provides not only syntax-highlight but also context-dependent utilities.
      So want to enable by default, but maybe slow, thus disable by default.
    --]]
    -- https://github.com/nixypanda/dotfiles/blob/f1db26ad1eb65bfbc16da8c498dd2734fb47f8e5/modules/nvim/lua/treesitter.lua#L2
    require('nvim-treesitter.configs').setup({
      ensure_installed = {
        -- This needs to be empty otherwise treesitter complains about
        -- directory being not being writable. All the installation of the
        -- parsers is done declaratively into an immutable location using nix,

        -- so we don't really need to specify anything there.
        -- https://github.com/NixOS/nixpkgs/issues/189838
      },
      highlight = { enable = true },
      incremental_selection = {
        enable = false, -- use wildfire-nvim
      },

      -- replace default indent to nvim-yati
      -- indent = { enable = false },
      -- yati = { enable = true },

      refactor = { highlight_definitions = { enable = true } },
      textobjects = {
        select = {
          enable = true,
          keymaps = {
            ["af"] = "@function.outer",
            ["if"] = "@function.inner",
            ["ac"] = "@class.outer",
            ["ic"] = "@class.inner",
            ["ab"] = "@block.outer",
            ["ib"] = "@block.inner",
            ["aa"] = "@parameter.outer",
            ["ia"] = "@parameter.inner",
          },
        },
      },

      additional_vim_regex_highlighting = false,
    })

    --[[
      Profiling. Use profile.nvim as below,
      and toggle filetype "nvim --clean <bigfile> '+setlocal ft='"
      https://www.reddit.com/r/neovim/comments/16nmpze/comment/k1k4dzu/?utm_source=share&utm_medium=web3x&utm_name=web3xcss&utm_term=1&utm_content=share_button
    --]]
    -- profile.nvim
    local should_profile = os.getenv("NVIM_PROFILE")
    if should_profile then
      require("profile").instrument_autocmds()
      if should_profile:lower():match("^start") then
        require("profile").start("*")
      else
        require("profile").instrument("*")
      end
    end

    local function toggle_profile()
      local prof = require("profile")
      if prof.is_recording() then
        prof.stop()
        vim.ui.input({ prompt = "Save profile to:", completion = "file", default = "profile.json" }, function(filename)
          if filename then
            prof.export(filename)
            vim.notify(string.format("Wrote %s", filename))
          end
        end)
      else
        prof.start("*")
      end
    end
    map("", "<f1>", toggle_profile)

    --[[
      The plugins that overlaps with IDE like shortcut-key and the other features only enable on native only

      autopair: nvim-autopairs
      VS code "editor.autoClosingBrackets"

      indent-blankline: hlchunk.nvim
      VS code "editor.renderIndentGuides"
    --]]
    -- nvim-autopairs
    require("nvim-autopairs").setup({
      check_ts = true,
    })
    -- hlchunk as indent-blankline-nvim alternative
    require("hlchunk").setup({
      chunk = { enable = true },
      indent = { enable = true },
      line_num = { enable = true },
      blank = { enable = true },
    })
  '';
in
{
  home.packages = with pkgs; [
    tree-sitter # core. important.

    # language-server for common
    typos-lsp # typos

    # custom command
    vimTemp

    (lib.my.removeAllDesktopIcons {
      package = config.programs.neovim.finalPackage;
    })
  ];
  programs.neovim = {
    enable = true;
    # For vscode-neovim. requires at least later than 0.10.0
    package = pkgs.neovim-unwrapped;
    withRuby = false;
    withPython3 = false;
    withNodeJs = false;
    vimAlias = true;
    # defaultEditor = true;  machine defines editor

    # under SCUDO, when using plugins sometimes crush. https://github.com/luvit/luv/issues/701
    plugins = with pkgs.vimPlugins; [
      # Look-and-feel
      github-nvim-theme
      transparent-nvim
      noice-nvim # some window UI
      gitsigns-nvim
      lualine-nvim # statusline
      # vim-illuminate # too slow
      alpha-nvim # startup page
      faster-nvim # feature switcher for big files.

      # Tools
      fzf-lua
      comment-nvim
      vim-tmux-navigator
      nvim-spectre # substitute menu
      nnn-vim
      lazygit-nvim
      vim-rooter # important. all command execute in project root.
      fidget-nvim # plugin loader notice
      hop-nvim # easymotion
      hlchunk-nvim # indent-blankline alternative
      hlargs-nvim
      (vimPluginFromGitHubRevWithDeps "1729faca1c6ae34520a6e531983a3737d3654ee1"
        "SUSTech-data/wildfire.nvim"
        [ nvim-treesitter ]
      ) # <CR> to select text considering treesitter units
      nvim-autopairs # autopair. lexima has the bug that makes ESC slow, so replace to this.
      nvim-surround # change braces. S) in visual works surround.
      nvim-spider # w/b moving
      which-key-nvim
      todo-comments-nvim
      treesj # splitting/joining blocks
      vim-wakatime
      (vimPluginFromGitHubRev "30433d7513f0d14665c1cfcea501c90f8a63e003" "stevearc/profile.nvim") # profiler. Use NVIM_PROFILER=1 to enable.

      # Lsp core
      nvim-lspconfig
      nvim-treesitter.withAllGrammars
      nvim-treesitter-context
      # (vimPluginFromGitHubRev "df3dc06076c6fe20a1dcd8643e712af5c252d042" "yioneko/nvim-yati")
      luasnip
      nvim-cmp
      lsp_signature-nvim
      cmp_luasnip
      cmp-nvim-lsp # suspect to be slow
      cmp-path
      cmp-buffer
      cmp-spell
      cmp-nvim-lsp-signature-help
      cmp-git
      cmp-rg
      cmp-treesitter
    ];
    extraConfig = ''
      """""""""""""""""""""""""""""""""""""""
      " common
      """""""""""""""""""""""""""""""""""""""

      " for windows
      set runtimepath+=$HOME/.vim,$HOME/.vim/after

      set encoding=utf-8
      set fileencodings=utf-8,iso-2022-jp,euc-jp,sjis
      set expandtab
      set tabstop=2
      set shiftwidth=2
      set softtabstop=0
      set smartindent
      set list
      set hidden
      set showcmd
      set ruler
      set laststatus=2
      set nobackup
      set noswapfile
      set writebackup
      set listchars=tab:>-
      set nocursorline
      autocmd InsertEnter,InsertLeave * set cursorline!
      set cmdheight=1
      set wildmenu
      set wildmode=longest:full,full
      set ignorecase
      set smartcase
      set wrapscan
      set hlsearch
      set showmatch
      set autochdir
      set nocompatible
      set number
      set scrolloff=7
      set nowrap
      set autochdir
      set fdc=2
      set fdm=indent
      set noequalalways
      set nofoldenable

      " OS check
      if has('win32')
        let ostype = "Win"
      elseif has('mac')
        let ostype = "Mac"
      else
        let ostype = system("uname")
      endif

      " colorsheme
      set background=dark
      set t_Co=256
      " colorscheme gruvbox
      autocmd VimEnter * hi Normal ctermbg=none guibg=none

      " change the leader key from "\" to ";" ("," is also popular)
      let mapleader=";"

      " disable ~/.vim/.netrwhist
      let g:netrw_dirhistmax = 0

      " clipboard. may not work on vim.
      " https://rcmdnk.com/blog/2019/05/27/computer-mac/
      set clipboard+=unnamedplus

      " Disable default plugins for fast startup {{{ https://qiita.com/yasunori-kirin0418/items/4672919be73a524afb47
        " TOhtml.
        let g:loaded_2html_plugin       = v:true

        " archive file open and browse.
        let g:loaded_gzip               = v:true
        let g:loaded_tar                = v:true
        let g:loaded_tarPlugin          = v:true
        let g:loaded_zip                = v:true
        let g:loaded_zipPlugin          = v:true

        " vimball.
        let g:loaded_vimball            = v:true
        let g:loaded_vimballPlugin      = v:true

        " netrw plugins.
        let g:loaded_netrw              = v:true
        let g:loaded_netrwPlugin        = v:true
        let g:loaded_netrwSettings      = v:true
        let g:loaded_netrwFileHandlers  = v:true

        " `GetLatestVimScript`.
        let g:loaded_getscript          = v:true
        let g:loaded_getscriptPlugin    = v:true

        " other plugins
        let g:loaded_man                = v:true
        let g:loaded_matchit            = v:true
        let g:loaded_matchparen         = v:true
        let g:loaded_shada_plugin       = v:true
        let g:loaded_spellfile_plugin   = v:true
        let g:loaded_tutor_mode_plugin  = v:true
        let g:did_install_default_menus = v:true
        let g:did_install_syntax_menu   = v:true
        let g:skip_loading_mswin        = v:true
        let g:did_indent_on             = v:true

        let g:did_load_ftplugin         = v:true
        let g:loaded_rrhelper           = v:true
      " }}}
      syntax on

      """""""""""""""""""""""""""""""""""""""
      " tmux
      """""""""""""""""""""""""""""""""""""""
      " See: https://qiita.com/izumin5210/items/d2e352de1e541ff97079
      nnoremap <silent> <C-w>h :TmuxNavigateLeft<cr>
      nnoremap <silent> <C-w>j :TmuxNavigateDown<cr>
      nnoremap <silent> <C-w>k :TmuxNavigateUp<cr>
      nnoremap <silent> <C-w>l :TmuxNavigateRight<cr>
      nnoremap <silent> <C-w>\\ :TmuxNavigatePrevious<cr>

      """""""""""""""""""""""""""""""""""""""
      " nnn
      """""""""""""""""""""""""""""""""""""""
      " VS Code style
      tnoremap <C-E> :NnnExplorer<CR>
      nnoremap <C-E> :NnnExplorer<CR>

      nnoremap <leader>n <cmd>NnnExplorer %:p:h<CR>
    '';
    extraLuaConfig = ''
      ${neovimExtraLuaConfigForAllEnvironment}
      if not vim.g.vscode then
        ${neovimExtraLuaConfigForNativeOnly}
      end
    '';
  };

  editorconfig = {
    enable = true;
    settings = {
      # http://editorconfig.org
      # base: google coding style
      "*" = {
        charset = "utf-8";
        end_of_line = "lf";
        indent_style = "space";
        indent_size = 2;
        insert_final_newline = true;
        trim_trailing_whitespace = true;
        max_line_length = 120; # own rule
      };
      # document
      "*.{markdown,md}" = {
        # google
        indent_size = 4;
        trim_trailing_whitespace = false;
      };
      "LICENSE" = {
        insert_final_newline = false;
      };
      # source
      "*.java" = {
        # google
        indent_size = 4;
      };
      "*.{py,py.tpl}" = {
        # google
        indent_size = 4;
      };
      "*.go" = {
        # effective go
        indent_size = 4;
        indent_style = "tab";
      };
      "*.rs" = {
        # style guide - Learn Rust
        indent_size = 4;
        max_line_length = 99;
      };
      "*.sh" = {
        # google
        shell_variant = "bash";
        switch_case_indent = true;
      };
      # config
      ".git*" = {
        indent_style = "tab";
        indent_size = 4;
      };
      # build
      "{Make,Docker,Earth}File" = {
        indent_style = "tab";
        indent_size = 4;
      };
    };
  };
}
