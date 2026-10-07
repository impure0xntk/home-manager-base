{ config, lib, pkgs, ... }:
let
  cfg = config.my.home.ide.zed;

  # Default settings (similar to vscode module)
  defaultSettings =
    let
      fontFamily = "Consolas";
    in {
      base_keymap = "VSCode";
      vim_mode = true;
      ui_font_size = 14;
      ui_font_family = fontFamily;
      buffer_font_size = 14;
      buffer_font_family = fontFamily;
      buffer_line_height = "comfortable";
      tab_size = 2;
      hard_tabs = false;
      autosave = "on_focus_change";

      # UI settings
      show_whitespaces = "all";
      preview_tabs = {
        enabled = false;
        enable_preview_from_file_finder = false;
      };
      status_bar = {
        "experimental.show" = false;
      };
      tab_bar = {
        show = false;
        show_tab_bar_buttons = false;
      };
      title_bar = {
        show_onboarding_banner = false;
        show_user_picture = false;
        show_sign_in = false;
      };
      sticky_scroll = {
        enabled = true;
      };
      gutter = {
        folds = false;
      };
      minimap = {
        show = "never";
      };

      # Editor behavior
      auto_indent = "syntax_aware";
      colorize_brackets = true;
      linked_edits = true;
      use_auto_surround = true;
      inlay_hints = {
        enabled = true;
      };
      soft_wrap = "none";
      format_on_save = "modifications";

      active_pane_modifiers = {
        border_size = 1.0;
        inactive_opacity = 0.8;
      };

      session = {
        trust_all_worktrees = true;
      };

      telemetry = {
        diagnostics = false;
        metrics = false;
      };

      theme = {
        mode = "dark";
        # dark = "GitHub Dark Dimmed";
        light = "One Light";
        dark = "One Dark";
      };
    };

  # Default keymaps
  defaultKeymaps =
  let
    group =
      context: bindings:
      {
        inherit context bindings;
      };

    sameContext =
      context: attrs:
      group context (lib.listToAttrs (
        map (x: {
          name = x.key;
          value = x.command;
        }) attrs
      ));
  in
  [
    (sameContext "Editor || Terminal" [
      {
        key = "ctrl-w h";
        command = "workspace::ActivatePaneLeft";
      }
      {
        key = "ctrl-w j";
        command = "workspace::ActivatePaneDown";
      }
      {
        key = "ctrl-w k";
        command = "workspace::ActivatePaneUp";
      }
      {
        key = "ctrl-w l";
        command = "workspace::ActivatePaneRight";
      }
    ])

    (sameContext "menu || Picker" [
      {
        key = "ctrl-n";
        command = "menu::SelectNext";
      }
      {
        key = "ctrl-p";
        command = "menu::SelectPrevious";
      }
      {
        key = "ctrl-j";
        command = "menu::SelectNext";
      }
      {
        key = "ctrl-k";
        command = "menu::SelectPrevious";
      }
    ])

    (sameContext "Editor && showing_completions" [
      {
        key = "ctrl-n";
        command = "menu::SelectNext";
      }
      {
        key = "ctrl-p";
        command = "menu::SelectPrevious";
      }
    ])

    (sameContext "Picker" [
      {
        key = "ctrl-n";
        command = "menu::SelectNext";
      }
      {
        key = "ctrl-p";
        command = "menu::SelectPrevious";
      }
    ])

    (sameContext "BufferSearchBar" [
      {
        key = "ctrl-h";
        command = "search::ToggleReplace";
      }
    ])
  ];

  defaultExtensions = with pkgs.zed-extensions; [
    github-theme
    git-firefly
    vscode-icons
    log
  ];

  mergedSettings = defaultSettings // cfg.userSettings;
  mergedKeymaps = defaultKeymaps ++ cfg.userKeymaps;
  mergedExtensions = defaultExtensions ++ cfg.extensions;
in
{
  options.my.home.ide.zed = {
    enable = lib.mkEnableOption "Zed editor";

    package = lib.mkPackageOption pkgs "zed" { };

    # Main settings - flexible attrset like upstream
    userSettings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Configuration written to Zed's settings.json. Use any valid Zed setting. Merged with defaultSettings.";
      example = {
        theme = "One Dark";
        base_keymap = "vscode";
        vim_mode = false;
        buffer_font_size = 14;
        buffer_font_family = "JetBrains Mono, Noto Sans JP";
        tab_size = 2;
        hard_tabs = false;
        auto_save = "on_focus_change";
        languages = {
          rust = { format_on_save = true; };
          python = { format_on_save = true; };
          typescript = { format_on_save = true; };
        };
        lsp = {
          rust_analyzer = {
            settings = {
              "rust-analyzer" = {
                checkOnSave = { command = "clippy"; };
              };
            };
          };
        };
        terminal = {
          font_size = 13;
          font_family = "JetBrains Mono";
          shell = "fish";
        };
        agent = {
          default_model = "anthropic/claude-3.5-sonnet";
          tool_permissions = { default = "confirm"; };
        };
        context_servers = {
          # MCP servers go here
        };
      };
    };

    # Keymap configuration - list of binding objects
    userKeymaps = lib.mkOption {
      type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
      default = [ ];
      description = "Keymap configuration written to Zed's keymap.json.";
      example = [
        { bindings = { "ctrl-right" = "editor::SelectLargerSyntaxNode"; }; }
        { context = "ProjectPanel && not_editing"; bindings = { "o" = "project_panel::Open"; }; }
      ];
    };

    # Extensions to install
    extensions = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "List of extensions to install via zed-install-extensions script. Use names from https://github.com/zed-industries/extensions/tree/main/extensions";
      example = with pkgs.zed-editor-extensions; [ nix ];
    };

    # Install remote server binary
    installRemoteServer = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to symlink Zed's remote server binary for remote connections.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Delegate to home-manager's official programs.zed-editor module
    programs.zed-editor = {
      enable = true;
      package = cfg.package;

      userSettings = mergedSettings;
      userKeymaps = mergedKeymaps;

      mutableUserSettings = false;
      mutableUserKeymaps = false;
      mutableUserTasks = false;
      mutableUserDebug = false;

      # Remote server
      installRemoteServer = cfg.installRemoteServer;
    };
    programs.zed-editor-extensions = {
      enable = true;
      packages = mergedExtensions;
    };
  };
}