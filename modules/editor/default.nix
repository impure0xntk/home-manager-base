{
  config,
  pkgs,
  lib,
  ...
}:
let
  # https://gist.github.com/nat-418/d76586da7a5d113ab90578ed56069509
  vimPluginFromGitHubRef =
    repo: ref:
    pkgs.unstable.vimUtils.buildVimPlugin {
      pname = "${lib.strings.sanitizeDerivationName repo}";
      version = ref;
      src = builtins.fetchGit {
        url = "https://github.com/${repo}.git";
        inherit ref;
      };
    };
  vimPluginFromGitHubRevWithDeps =
    repo: rev: deps:
    pkgs.unstable.vimUtils.buildVimPlugin {
      pname = "${lib.strings.sanitizeDerivationName repo}";
      version = rev;
      dependencies = deps;
      src = builtins.fetchGit {
        url = "https://github.com/${repo}.git";
        inherit rev;
      };
    };
  vimPluginFromGitHubRev = repo: rev: vimPluginFromGitHubRevWithDeps repo rev [ ];

  vimTemp = pkgs.unstable.writeShellApplication {
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
  neovim-treesitter-parsers-and-queries =
  let
    parsers = with pkgs.unstable; [ (tree-sitter.withPlugins (_: tree-sitter.allGrammars)) ];
    queries = pkgs.unstable.vimPlugins.nvim-treesitter.withAllGrammars.dependencies;
  in pkgs.unstable.symlinkJoin {
    name = "neovim-treesitter-parsers-and-queries";
    paths = [ parsers ] ++ queries;
    postBuild = ''
      mkdir -p $out/parser
      for f in $out/*.so; do
        # Exclude built-in grammers: ["vim" "lua" "c" "help"]
        # to avoid conflict with tiny-cmdline
        BUILTIN_GRAMMARS="vim lua c help"
        LIBRARY_NAME=''${f##*/}
        LIBRARY_NAME_NO_EXT=''${LIBRARY_NAME%.*}
        if [[ ! $BUILTIN_GRAMMARS =~ $LIBRARY_NAME_NO_EXT  ]]; then
          mv $f $out/parser/
        fi
      done
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
    -- comment-nvim
    require('Comment').setup()
    --   Ctrl+/ to comment-out line. _ as slash
    map("n", "<C-_>", require('Comment.api').toggle.linewise.current, { noremap = true, silent = true })
    map('v', '<C-_>', '<ESC><CMD>lua require("Comment.api").toggle.linewise(vim.fn.visualmode())<CR>', { noremap = true, silent = true })
    -- textobject incremental selection, such as wildfire
    vim.keymap.set("n", "<CR>", function()
      vim.cmd("normal! v")
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("an", true, false, true), "x", false)
    end, { desc = "Incremental selection" })
    vim.keymap.set("x", "<CR>", function()
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("an", true, false, true), "x", false)
    end, { desc = "Incremental selection" })
    vim.keymap.set("x", "<BS>", function()
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("in", true, false, true), "x", false)
    end, { desc = "Decremental selection" })
    -- nvim-spider for smartword
    require("spider").setup {
      subwordMovement = false,
    }
    map({ "n", "o", "x" }, "w", "<cmd>lua require('spider').motion('w')<CR>")
    map({ "n", "o", "x" }, "e", "<cmd>lua require('spider').motion('e')<CR>")
    map({ "n", "o", "x" }, "b", "<cmd>lua require('spider').motion('b')<CR>")

    --[[
      Treesitter related config
      https://zeta.ws/nvim/#4-nvim-treesitter-%E3%82%B7%E3%83%B3%E3%82%BF%E3%83%83%E3%82%AF%E3%82%B9%E3%83%8F%E3%82%A4%E3%83%A9%E3%82%A4%E3%83%88
    --]]
    vim.api.nvim_create_autocmd("FileType", {
      callback = function(args)
        local lang = vim.treesitter.language.get_lang(args.match)
        if not lang or lang == "cmd" then return end

        local parser = vim.treesitter.get_parser(args.buf, lang)
        if not parser then
          return
        end

        vim.treesitter.start(args.buf, lang)
      end,
    })
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
    -- statusline
    require('incline').setup()
    vim.opt.laststatus = 0 -- For no statusline
    -- modes
    require("modes").setup({
      colors = {
        copy = '#FFEE55',
        delete = '#DC669B',
        insert = '#55AAEE',
        visual = '#DD5522',
      },
      line_opacity = {
        copy = 0.4,
        delete = 0.4,
        insert = 0.4,
        visual = 0.4,
      },
    })
    -- alpha-nvim
    require('alpha').setup(require('alpha.themes.startify').config)
    require('mini.cursorword').setup()

    -- UI improvement
    require('vim._core.ui2').enable({})
    vim.o.cmdheight = 0 -- Ready for tiny-cmdline
    require("tiny-cmdline").setup({
      native_types = {},
      on_reposition = require("tiny-cmdline").adapters.blink, -- For blink.cmp
    })
    require('mini.notify').setup()
    vim.api.nvim_create_user_command('NotifyHistory', function()
      MiniNotify.show_history()
    end, { desc = 'Show notify history' })

    require('mini.hipatterns').setup({
      highlighters = {
        fixme = { pattern = '%f[%w]()FIXME()%f[%W]', group = 'MiniHipatternsFixme' },
        hack  = { pattern = '%f[%w]()HACK()%f[%W]',  group = 'MiniHipatternsHack'  },
        todo  = { pattern = '%f[%w]()TODO()%f[%W]',  group = 'MiniHipatternsTodo'  },
        note  = { pattern = '%f[%w]()NOTE()%f[%W]',  group = 'MiniHipatternsNote'  },
      },
    })

    require('render-markdown').setup({
      sign = { enabled = false, },
    })

    require('treesitter-context').setup()

    --[[
      The plugins that uses another window/pane/tab/tmux only enable on native only
    --]]
    -- fzf-lua
    require("fzf-lua").setup()
    map("n", "<C-P>", require('fzf-lua').oldfiles, { desc = "Fzf Files MRU" })
    map("n", "<Leader>fd", require('fzf-lua').files, { desc = "Fzf Files fd" })
    map("n", "<Leader>rg", require('fzf-lua').grep_project, { desc = "Fzf Grep Project" })
    map("n", "<A-p>", "<CMD>lua require('fzf-lua').commands()<CR>", { desc = "Fzf Command", silent = true })
    map('n', "<A-.>", require('fzf-lua').lsp_code_actions, { desc = "Fzf Lsp code actions" })
    map('n', "<A-m>", require('fzf-lua').lsp_workspace_diagnostics, { desc = "Fzf Lsp workspace diagnostic" })

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

    -- LSP and completions (native Neovim 0.12+ completion)
    vim.lsp.inlay_hint.enable(true)

    -- blink.cmp setup for non-LSP completion
    require('blink.cmp').setup({
      completion = {
        ghost_text = { enabled = true },
        list = { selection = {
          preselect = true,
          auto_insert = false,
        }},
        documentation = { auto_show = false }
      },
      sources = {
        default = { 'path', 'snippets', 'buffer' }
      },
      fuzzy = {
        -- Use Rust binary forcibly: see the derivation of blink-cmp
        implementation = "rust",
        prebuilt_binaries = { download = false },
      },
      keymap = {
        preset = "enter"
      },
    })

    -- Native LSP completion settings
    vim.opt.completeopt = { 'menu', 'menuone', 'noselect', 'popup' }
    vim.o.pumwidth = 1  -- Single-column popup like cmp

    -- Enable native LSP completion on LspAttach
    vim.api.nvim_create_autocmd('LspAttach', {
      callback = function(ev)
        local client = vim.lsp.get_client_by_id(ev.data.client_id)
        if client then
          if client:supports_method('textDocument/completion') then
            vim.lsp.completion.enable(true, client.id, ev.buf, { autotrigger = true })
          end
          if client:supports_method("textDocument/codeLens") then
            vim.lsp.codelens.enable(true, { bufnr = ev.buf })
          end
        end
        vim.diagnostic.config({ virtual_text = false, virtual_lines = { current_line = true }, })
      end,
    })
    local lsp_mappings = {
      { 'gD', vim.lsp.buf.declaration },
      { 'gd', vim.lsp.buf.definition },
      { '<C-k>', vim.lsp.buf.signature_help },
    }
    for i, mapping in pairs(lsp_mappings) do
      map('n', mapping[1], function() mapping[2]() end)
    end
    map('x', '\\a', function() vim.lsp.buf.code_action() end)

    -- LSP config
    local servers = ${lib.generators.toLua {} config.my.home.editors.lspConfig}
    for name, cfg in pairs(servers) do
      vim.lsp.config(name, cfg)
      vim.lsp.enable(name)
    end

    --[[
      The plugins that overlaps with IDE like shortcut-key and the other features only enable on native only

      indent-blankline: mini-indentscope
      VS code "editor.renderIndentGuides"
    --]]
    require('mini.indentscope').setup()
    vim.opt.listchars = { leadmultispace = "│ ", tab = '» ', trail = '·', nbsp = '␣' }
    vim.opt.list = true
  '';
in
{
  options.my.home.editors = {
    lspConfig = lib.mkOption {
      type = lib.types.attrs;
      default = config.my.home.editors.lspConfigPreset;
      description = ''Neovim LSP configuration'';
      example = config.my.home.editors.lspConfigPreset // {
        typos_lsp = {
          cmd = [ "${lib.getExe pkgs.unstable.typos-lsp}" ];
          cmd_env = { RUST_LOG = "typos_lsp=error"; };
          init_options = {
            diagnosticSeverity = "Warning";
          };
        };
      };
    };
    lspConfigPreset = lib.mkOption {
      type = lib.types.attrs;
      default = {
        typos_lsp = {
          cmd = [ "${lib.getExe pkgs.unstable.typos-lsp}" ];
          cmd_env = { RUST_LOG = "typos_lsp=error"; };
          init_options = {
            diagnosticSeverity = "Warning";
          };
        };
        codebook_lsp = {
          cmd = [ "${lib.getExe pkgs.unstable.codebook}" "serve" ];
        };
      };
      description = ''Neovim LSP configuration preset. DO NOT EDIT'';
    };

  };
  config = {
    home.packages = with pkgs.unstable; [
      # custom command
      vimTemp

      (lib.my.removeAllDesktopIcons {
        package = config.programs.neovim.finalPackage;
      })
    ];
    programs.neovim = {
      enable = true;
      # For vscode-neovim. requires at least later than 0.10.0
      package = pkgs.unstable.neovim-unwrapped;
      withRuby = false;
      withPython3 = false;
      withNodeJs = false;
      vimAlias = true;
      # defaultEditor = true;  machine defines editor

      # under SCUDO, when using plugins sometimes crush. https://github.com/luvit/luv/issues/701
      plugins = with pkgs.unstable.vimPlugins; [
        # Look-and-feel
        github-nvim-theme
        transparent-nvim
        tiny-cmdline-nvim
        mini-notify
        mini-cursorword
        incline-nvim
        gitsigns-nvim
        alpha-nvim # startup page
        faster-nvim # feature switcher for big files.
        render-markdown-nvim

        # Tools
        fzf-lua
        comment-nvim
        vim-tmux-navigator
        nnn-vim
        lazygit-nvim
        vim-rooter # important. all command execute in project root.
        mini-indentscope
        hlargs-nvim
        nvim-spider # w/b moving
        mini-hipatterns
        vim-wakatime
        blink-cmp
        friendly-snippets  # blink-cmp snippets source
        (vimPluginFromGitHubRev "mvllow/modes.nvim" "fc7bc0141500d9cf7c14f46fca846f728545a781")
        nvim-treesitter-context

        # Syntax
        neovim-treesitter-parsers-and-queries # self-maid
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
  };
}
