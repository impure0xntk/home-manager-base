{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.programs.vscode;
  settings = cfg.profiles.default.userSettings;
  cfgNetworks = config.my.home.networks;

  proxySettings = lib.optionalAttrs cfgNetworks.proxy.enable (
    lib.my.flatten "_flattenIgnore" {
      # According to description, these respect environment variables,
      # but not work, so define explicitly.
      http = {
        proxyStrictSSL = false;
        proxy = cfgNetworks.proxy.default;
        noProxy = [
          "127.0.0.1"
          "localhost"
          cfgNetworks.hostname
        ];
      };

      # Some extension needs each settings: e.g. sonarlint and xml,
      # but conflict with other args like jvmargs.
      # Thus, sets from each modules.
    }
  );

  extensionListName = lib.flatten [
    (lib.mapAttrsToList (
      n: v: (lib.forEach v.extensions (ext: "${ext.vscodeExtPublisher}.${ext.vscodeExtName}"))
    ) config.programs.vscode.profiles)
  ];
  extensionList = lib.flatten [
    (lib.mapAttrsToList (
      n: v:
      (lib.forEach v.extensions (ext: "${ext.vscodeExtPublisher}.${ext.vscodeExtName}@${ext.version}"))
    ) config.programs.vscode.profiles)
  ];

  configDirName =
    {
      "vscode" = "Code";
      "vscode-insiders" = "Code - Insiders";
      "vscodium" = "VSCodium";
      "openvscode-server" = "OpenVSCode Server";
      "windsurf" = "Windsurf";
      "cursor" = "Cursor";
    }
    .${cfg.package.pname};
  configDir = "${config.xdg.configHome}/${configDirName}";

  binName =
    {
      "vscode" = "code";
      # "vscode-insiders" = "Code - Insiders";
      "vscodium" = "codium";
      # "openvscode-server" = "OpenVSCode Server";
      # "windsurf" = "Windsurf";
      # "cursor" = "Cursor";
    }
    .${cfg.package.pname};

  # Can install extension from vscode integrated terminal only.
  # So provide script and use it from vscode.
  extensionInstallScript = pkgs.writeShellScriptBin "code-install-extensions" ''
    if ! command -v ${binName}; then
      echo "${binName}: not found" >&2
      exit 1
    fi
    for ext in ${lib.concatStringsSep " " extensionList}; do
      ${binName} --install-extension $ext || true
    done
  '';

  shellAliases = {
    "${binName}" = "${binName} -r";
  };
in
{
  options.my.home.ide.vscode = {
    package = lib.mkPackageOption pkgs "vscode" { };
    configDir = lib.mkOption {
      type = lib.types.path;
      default = configDir;
      description = "DO NOT EDIT.";
    };
    languages = {
      chat = lib.mkOption {
        type = lib.types.str;
        default = "ja-JP";
      };
      voice = lib.mkOption {
        type = lib.types.str;
        default = "ja-JP";
      };
    };
  };

  config = {
    programs.bash.shellAliases = shellAliases;
    home.packages = [ extensionInstallScript ];

    programs.vscode = {
      enable = true;
      package = config.my.home.ide.vscode.package;
      profiles.default = {
        enableUpdateCheck = false; # Disable VSCode self-update and let Home Manager to manage VSCode versions instead.
        enableExtensionUpdateCheck = false; # Disable extensions auto-update and let nix4vscode manage updates and extensions

        extensions = pkgs.nix4vscode.forVscode [
          # not found in openvsx registry
          "ms-vscode-remote.remote-wsl"
          "ms-vscode-remote.remote-ssh"
          "ms-vscode-remote.remote-ssh-edit"
          "ms-vscode-remote.remote-containers"
          "visualstudioexptteam.vscodeintellicode"
          "visualstudioexptteam.intellicode-api-usage-examples"
          "ms-vscode.vscode-speech"
          "ms-vscode.vscode-speech-language-pack-${config.my.home.ide.vscode.languages.voice}"

          "christian-kohler.path-intellisense" # maybe exists in both.
          "zainchen.json"

          # found
          "usernamehw.errorlens"
          "asvetliakov.vscode-neovim"
          "vspacecode.whichkey"
          "alefragnani.bookmarks"
          "mkhl.direnv"
          "shardulm94.trailing-spaces"

          "donjayamanne.githistory"
          "eamodio.gitlens"
          "codezombiech.gitignore"
          "mhutchie.git-graph"

          "GitHub.vscode-pull-request-github"

          "redhat.vscode-yaml"
          "sumneko.lua"
          "ms-vscode.makefile-tools"
          "tamasfe.even-better-toml"

          "gruntfuggly.todo-tree"
          "oderwat.indent-rainbow"

          "mhutchie.git-graph"
          "wmaurer.change-case"
          "streetsidesoftware.code-spell-checker"
          "tekumara.typos-vscode"

          "wakatime.vscode-wakatime"
          "funkyremi.vscode-google-translate"

          "github.github-vscode-theme"

          "tompollak.lazygit-vscode"
          "eriklynd.json-tools"
          "richie5um2.vscode-sort-json"
          "tyriar.sort-lines"
          "fnando.linter" # TODO: remove after replacing textlint extension.
          "sleistner.vscode-fileutils"
          "rioj7.command-variable"
          "augustocdias.tasks-shell-input"
          "gruntfuggly.triggertaskonsave" # Not used, but useful
          "s-nlf-fh.glassit"
        ];
        # Refs:
        #  Look and feel: https://dev.to/andrewgeorge/minimal-vscode-ui-343e
        userSettings =
          {
            # This section is to avoid infinite recursion of programs.vscode.userSettings.
            # If possible, edit settings into lib.my.flatten to ensure nix attrset.
            "!!! Notice !!!" = lib.mkOrder 100 "This file is generated by home-manager. Do not edit it.";
            "settingsSync.ignoredSettings" = lib.mkOrder 1600 (
              # after lib.mkAfter: 1500
              lib.mapAttrsToList (k: v: k) settings
            );
            # Settings that cannot use flatten
            "github.copilot.enable" = lib.mkDefault {
              # Disable by default
              "*" = false;
            };
          }
          // (lib.my.flatten "_flattenIgnore" rec {
            telemetry.telemetryLevel = "off";

            accessibility.voice = {
              keywordActivation = "chatInContext";
              speechLanguage = config.my.home.ide.vscode.languages.voice; # TODO: option
            };
            breadcrumbs.enabled = false;

            dev.containers = {
              executeInWSL = true;
              logLevel = "trace";
            };
            debug = {
              onTaskErrors = "debugAnyway";
              terminal.clearBeforeReusing = true;
            };
            diffEditor.ignoreTrimWhitespace = false;

            editorconfig.generateAuto = false;

            errorLens = {
              enabledDiagnosticLevels = [
                "error"
                "warning"
              ];
              fontStyleItalic = true;
            };

            # "explorer.openEditors.visible" = 0;
            explorer.decorations.colors = false;

            # Workaround of "Signature verification failed with 'UnknownError' error."
            extensions = {
              autoUpdate = false;
              verifySignature = false;
              ignoreRecommendations = true;
            };

            editor = {
              autoClosingBrackets = "beforeWhitespace";
              autoClosingQuotes = "beforeWhitespace";
              autoSurround = "languageDefined";
              bracketPairColorization.enabled = true;
              cursorSmoothCaretAnimation = "on";
              cursorBlinking = "phase";
              # defaultFormatter = "EditorConfig.EditorConfig";
              dragAndDrop = false;
              fontFamily = "Consolas, 'Noto Sans JP', monospace";
              formatOnSave = true;
              formatOnSaveMode = "modifications";
              guides = {
                bracketPairs = "active";
                highlightActiveBracketPair = true;
                bracketPairsHorizontal = false;
              };
              glyphMargin = false; # Experimental: remove left margin to toggle breakpoint.
              inlayHints.enabled = "onUnlessPressed";
              linkedEditing = true;
              minimap.enabled = false;
              renderControlCharacters = true;
              renderWhitespace = "all";
              scrollbar = {
                horizontalScrollbarSize = 8; # default: 14
                verticalScrollbarSize = 8; # default: 14
              };
              showFoldingControls = "never";
              smoothScrolling = true;
              stickyScroll.enabled = true;
              tabSize = 2;
              wordWrap = "off";
            };
            git = {
              autofetch = true;
              confirmSync = false;
              enableSmartCommit = true;
              ignoreLegacyWarning = true;
              terminalAuthentication = false;
            };

            remote = {
              autoForwardPorts = false;
              SSH = {
                enableRemoteCommand = true;
                useLocalServer = false;
              };
              WSL = {
                fileWatcher = {
                  polling = true;
                  pollingInterval = 60000;
                };
              };
            };
            search.searchView.keywordSuggestions = true;
            settingsSync.ignoredExtensions = extensionListName;

            task.problemMatchers.neverPrompt = {
              # no flatten
              "shell" = true;
              _flattenIgnore = true;
            };

            terminal.integrated = {
              commandsToSkipShell = [
                "-workbench.action.quickOpen" # to respect ctrl+p.
              ];
              defaultProfile.linux = "tmux";
              macOptionClickForcesSelection = true;
              profiles.linux = {
                # no flatten
                "bash" = {
                  "icon" = "terminal-bash";
                  "path" = "${pkgs.bash}/bin/bash";
                };
                "fish" = {
                  "icon" = "terminal";
                  "path" = "${pkgs.fish}/bin/fish";
                };
                "tmux" = {
                  "icon" = "terminal-tmux";
                  "path" = "${pkgs.tmux}/bin/tmux";
                };
                _flattenIgnore = true;
              };
              scrollback = 5000;
              shellIntegration = {
                decorationsEnabled = "never";
                enabled = false;
              };
            };
            window = {
              commandCenter = false;
              customTitleBarVisibility = "never";
              density.editorTabHeight = "compact";
              menuBarVisibility = "toggle";
              titleBarStyle = "custom";
              title = " ";
            };
            workbench = {
              activityBar.location = "hidden";
              layoutControl.enabled = false;
              colorTheme = "GitHub Dark Dimmed";
              editor = {
                enablePreview = false;
                enablePreviewFromQuickOpen = false;
                editorActionsLocation = "hidden";
                showTabs = "single"; # To hide all, set none
              };
              sideBar.location = "right";
              statusBar.visible = false;
            };
            zenMode.showTabs = workbench.editor.showTabs;

            # Application specific settings
            redhat.telemetry.enabled = false; # affects all redhat extensions, e.g. java, xml, yaml...
            gitlens = {
              showWhatsNewAfterUpgrades = false;
              plusFeatures.enabled = false;
              liveshare.allowGuestAccess = false;
              telemetry.enabled = false;
              cloudPatches.enabled = false;
              views.remotes.files.layout = "tree";
            };
            lazygit-vscode = {
              lazygitPath = "${config.programs.lazygit.package}/bin/lazygit";
              autoMaximizeWindow = true;
            };
            glassit.alpha = 235; # Transparency
            # vscode-neovim integration
            extensions.experimental.affinity = {
              "asvetliakov.vscode-neovim" = lib.mkIf config.programs.neovim.enable 1;
              _flattenIgnore = true;
            };
            todo-tree = {
              general.tags = [
                # Default
                "BUG"
                "HACK"
                "FIXME"
                "TODO"
                "XXX"
                "[ ]"
                "[x]"
                # Additional
                "todo"
                "fixme"
                "PERF"
                "perf"
              ];
              highlights = {
                defaultHighlight = {
                  _flattenIgnore = true;
                  foreground = "#FFFFFF"; # white
                  background = "#808080"; # grey
                  type = "tag";
                };
                customHighlight = {
                  _flattenIgnore = true;
                  # like TODO Highlight
                  "TODO" = {
                    background = "#FDBC3E"; # vivid orange
                    icon = "check";
                  };
                  "FIXME" = {
                    background = "#EE6492"; # pink
                    icon = "bug";
                  };
                };
              };
            };
            trailing-spaces = {
              deleteModifiedLinesOnly = true;
              trimOnSave = true;
            };
            typos.path = "${pkgs.typos-lsp}/bin/typos-lsp";
            linter = {
              enabled = true;
              cache = true;
              runOnTextChange = false;
            };
            vscodeGoogleTranslate.preferredLanguage = "English";
          })
          // proxySettings;

        userTasks = {
          version = "2.0.0";
          tasks =
            let
              linterTask =
                {
                  name,
                  command,
                  args,
                  pattern,
                }:
                {
                  # DO NOT use "background" and related settings.
                  # Trigger Task on Save covers it.
                  inherit command args;
                  "label" = "${name} current file";
                  "type" = "shell";
                  "detail" = "Run ${name} on current file";
                  "presentation" = {
                    "reveal" = "never";
                  };
                  "problemMatcher" = {
                    "owner" = name;
                    "fileLocation" = "autoDetect";
                    "pattern" = pattern;
                  };
                };
            in
            [
              # https://tekunabe.hatenablog.jp/entry/2020/10/24/ansible_stumble_20
              # (linterTask {
              #   name = "yamllint";
              #   command = "${pkgs.yamllint}/bin/yamllint";
              #   args = ["-f" "parsable" "\${file}"];
              #   pattern = [{
              #     # ...
              #   }];
              # })
            ];
        };
        keybindings =
          let
            swap =
              {
                keyBefore,
                keyAfter,
                command,
                when ? null,
              }:
              [
                {
                  key = keyBefore;
                  command = "-" + command;
                  inherit when;
                }
                {
                  key = keyAfter;
                  inherit command when;
                }
              ];
            sameWhen = when: attrs: lib.forEach attrs (attr: attr // { inherit when; });
            swapKeysAttrs = attrs: lib.flatten (lib.forEach attrs (attr: swap attr));

            bind = key: command: when: { inherit key command when; };
            bind' = key: command: { inherit key command; };

            editor =
              [
                {
                  key = "ctrl+h";
                  command = "-editor.action.startFindReplaceAction";
                  when = "editorFocus || editorIsOpen";
                }
                {
                  # For terminal editor tool: conflict with tmux
                  key = "ctrl+w";
                  command = "-workbench.action.terminal.killEditor";
                  when = "terminalEditorFocus && terminalFocus && terminalHasBeenCreated || terminalEditorFocus && terminalFocus && terminalProcessSupported";
                }
              ]
              ++ sameWhen "editorFocus || terminalEditorFocus" [ # terminalEditorFocus for Claude Code
                {
                  key = "ctrl+w h";
                  command = "workbench.action.focusLeftGroup";
                }
                {
                  key = "ctrl+w j";
                  command = "workbench.action.focusBelowGroup";
                }
                {
                  key = "ctrl+w k";
                  command = "workbench.action.focusAboveGroup";
                }
                {
                  key = "ctrl+w l";
                  command = "workbench.action.focusRightGroup";
                }
              ]
              ++ sameWhen "editorFocus && !isAuxiliaryWindowFocusedContext" [
                {
                  key = "ctrl+g h";
                  command = "workbench.action.decreaseViewWidth";
                }
                {
                  key = "ctrl+g j";
                  command = "workbench.action.increaseViewHeight";
                }
                {
                  key = "ctrl+g k";
                  command = "workbench.action.decreaseViewHeight";
                }
                {
                  key = "ctrl+g l";
                  command = "workbench.action.increaseViewWidth";
                }
              ];

            list = sameWhen "listFocus" [
              # # Move focus. these affect also problems
              {
                key = "ctrl+n";
                command = "list.focusDown";
              }
              {
                key = "ctrl+p";
                command = "list.focusUp";
              }
              {
                key = "ctrl+j";
                command = "list.focusDown";
              }
              {
                key = "ctrl+k";
                command = "list.focusUp";
              }
            ];

            codeAction = sameWhen "codeActionMenuVisible" [
              {
                key = "ctrl+p";
                command = "selectPrevCodeAction";
              }
              {
                key = "ctrl+n";
                command = "selectNextCodeAction";
              }
              {
                key = "ctrl+oem_4";
                command = "hideCodeActionWidget";
              }
            ];

            suggestion = lib.flatten [
              {
                key = "ctrl+n";
                command = "editor.action.triggerSuggest";
                when = "editorHasCompletionItemProvider && textInputFocus && !editorReadonly";
              }
              {
                key = "ctrl+k";
                command = "acceptSelectedSuggestion";
              }
              {
                key = "ctrl+[";
                command = "search.action.cancel";
                when = "listFocus && searchViewletVisible";
              }
              (sameWhen "editorTextFocus && suggestWidgetMultipleSuggestions && suggestWidgetVisible" [
                {
                  key = "ctrl+n";
                  command = "selectNextSuggestion";
                }
                {
                  key = "ctrl+p";
                  command = "selectPrevSuggestion";
                }
              ])
              (sameWhen "editorTextFocus && parameterHintsMultipleSignatures && parameterHintsVisible" [
                {
                  key = "ctrl+n";
                  command = "showNextParameterHint";
                }
                {
                  key = "ctrl+p";
                  command = "showPrevParameterHint";
                }
              ])
            ];

            quickOpen = lib.flatten [
              # When focus terminal, disable ctrl+p for terminal.
              {
                key = "ctrl+shift+e";
                command = "-workbench.action.quickOpenNavigatePreviousInFilePicker";
                when = "inFilesPicker && inQuickOpen";
              }
              (sameWhen "inQuickOpen" [
                # Command palette
                {
                  key = "ctrl+n";
                  command = "workbench.action.quickOpenSelectNext";
                }
                {
                  key = "ctrl+p";
                  command = "workbench.action.quickOpenSelectPrevious";
                }
              ])
            ];

            snippet = lib.flatten [
              (swapKeysAttrs [
                {
                  keyBefore = "tab";
                  keyAfter = "ctrl+k";
                  command = "insertSnippet";
                  when = "editorTextFocus && hasSnippetCompletions && !editorTabMovesFocus && !inSnippetMode";
                }
                {
                  keyBefore = "shift+escape";
                  keyAfter = "ctrl+oem_6";
                  command = "leaveSnippet";
                  when = "editorTextFocus && inSnippetMode";
                }
              ])
              (sameWhen "editorTextFocus && hasNextTabstop && inSnippetMode" (swapKeysAttrs [
                {
                  keyBefore = "tab";
                  keyAfter = "ctrl+k";
                  command = "jumpToNextSnippetPlaceholder";
                }
                {
                  keyBefore = "shift+tab";
                  keyAfter = "ctrl+h";
                  command = "jumpToPrevSnippetPlaceholder";
                }
              ]))
            ];

            terminal = lib.flatten [
              ## Move cursor in terminal
              {
                key = "ctrl+f";
                command = "cursorRight";
                when = "terminalFocus";
              }
              {
                # Disable conflicted keybind: open terminal and vscode escape
                key = "ctrl+oem_3";
                command = "-vscode-neovim.escape";
                when = "editorTextFocus && neovim.init && editorLangId not in 'neovim.editorLangIdExclusions'";
              }
              {
                key = "ctrl+shift+g";
                command = "workbench.action.terminal.focusTabs";
                when = "terminalFocus && terminalHasBeenCreated || terminalFocus && terminalProcessSupported || terminalHasBeenCreated && terminalTabsFocus || terminalProcessSupported && terminalTabsFocus";
              }
              (sameWhen "terminalFocus && terminalProcessSupported" (swapKeysAttrs [
                {
                  keyBefore = "shift+pageup";
                  keyAfter = "ctrl+shift+b";
                  command = "workbench.action.terminal.scrollUpPage";
                }
                {
                  keyBefore = "ctrl+alt+pageup";
                  keyAfter = "ctrl+shift+k";
                  command = "workbench.action.terminal.scrollUp";
                }
                {
                  keyBefore = "ctrl+alt+pagedown";
                  keyAfter = "ctrl+shift+j";
                  command = "workbench.action.terminal.scrollDown";
                }
                {
                  keyBefore = "shift+pagedown";
                  keyAfter = "ctrl+shift+f";
                  command = "workbench.action.terminal.scrollDownPage";
                }
              ]))
            ];

            problems = lib.flatten [
              {
                key = "ctrl+u";
                command = "problems.action.clearFilterText";
                when = "problemsFilterFocus";
              }
              (swapKeysAttrs [
                {
                  keyBefore = "ctrl+f";
                  keyAfter = "ctrl+oem_2";
                  command = "problems.action.focusFilter";
                  when = "focusedView == 'workbench.panel.markers.view'";
                }
                {
                  keyBefore = "ctrl+down";
                  keyAfter = "ctrl+oem_6";
                  command = "problems.action.focusProblemsFromFilter";
                  when = "problemsFilterFocus";
                }
              ])
            ];

            search = lib.flatten [
              {
                key = "ctrl+[";
                command = "search.action.cancel";
                when = "listFocus && searchViewletVisible";
              }
              (sameWhen "inputBoxFocus && searchViewletVisible" [
                # Search
                {
                  key = "ctrl+n";
                  command = "search.focus.nextInputBox";
                }
                {
                  key = "ctrl+p";
                  command = "search.focus.prevInputBox";
                }
              ])
            ];

            breadcrumbs = lib.flatten [
              {
                key = "ctrl+shift+oem_period";
                command = "-breadcrumbs.toggleToOn";
                when = "!config.breadcrumbs.enabled";
              }
              (sameWhen "breadcrumbsPossible" [
                {
                  key = "ctrl+shift+oem_period";
                  command = "-breadcrumbs.focusAndSelect";
                }
                {
                  key = "ctrl+shift+oem_1";
                  command = "-breadcrumbs.focus";
                }
              ])
            ];

            shortcut = [
              # Which Key extension integration
              {
                key = "ctrl+shift+oem_2"; # oem_2 = slash
                command = "whichkey.show";
                when = "editorTextFocus";
              }
            ];
          in
          [
            # Note
            {
              key = "ctrl+alt+escape";
              command = "!!! Notice !!!";
              when = "This file is generated by home-manager. Do not edit it.";
            }
            # Global
            {
              key = "ctrl+m";
              command = "-editor.action.toggleTabFocusMode";
            }
            {
              key = "ctrl+b";
              command = "workbench.action.closeSidebar";
              when = "sideBarFocus";
            }
            {
              key = "ctrl+b";
              command = "workbench.action.closeAuxiliaryBar";
              when = "auxiliaryBarFocus";
            }
            ## Disable binding that conflicts with vim keybinding.
            {
              key = "ctrl+j";
              command = "-workbench.action.togglePanel";
            }
            {
              key = "ctrl+g";
              command = "-workbench.action.gotoLine";
            }
            {
              key = "ctrl+g";
              command = "-workbench.action.terminal.goToRecentDirectory";
              when = "terminalFocus && terminalHasBeenCreated || terminalFocus && terminalProcessSupported";
            }
            # Sidebar
            {
              # workaround: https://github.com/microsoft/vscode/issues/197453#issue-1977451720
              key = "ctrl+shift+e";
              command = "workbench.view.explorer";
              # when = "viewContainer.workbench.view.explorer.enabled";
            }
            # Panel
            {
              key = "ctrl+shift+u";
              command = "workbench.action.toggleMaximizedPanel";
              when = "panelFocus";
            }
            # Hover
            {
              key = "ctrl+oem_1";
              command = "editor.action.showHover";
              when = "editorTextFocus";
            }
          ]
          ++ editor
          ++ list
          ++ codeAction
          ++ suggestion
          ++ quickOpen
          ++ snippet
          ++ terminal
          ++ problems
          ++ search
          ++ breadcrumbs
          ++ shortcut;
      };
    };
  };
}
