{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.home.ai;

  # Use pre-defined provider
  qwen-code' = pkgs.writeShellScriptBin "qwen" ''
    export OPENAI_BASE_URL="${(searchModelByRole "chat").url}"
    export OPENAI_API_KEY="dummy"
    export OPENAI_MODEL="''${1:-${(searchModelByRole "chat").model}}"
    if [ $# -gt 0 ]; then
      shift
    fi
    ${pkgs.qwen-code}/bin/qwen "$@"
  '';

  # Map to include provider URL along with the model
  # expected result format:
  # [
  #   {
  #     provider = "ollama";
  #     url = "http://localhost:11434";
  #     model = "gemma3:12b";
  #   }
  # ]
  searchModelByRole =
    role:
    let
      models = builtins.concatLists (
        builtins.map (
          provider:
          builtins.filter (m: builtins.elem role m.roles) (
            builtins.map (m_: {
              inherit (provider) url;
              inherit (m_) model roles;
              provider = provider.name;
            }) provider.models
          )
        ) cfg.providers
      );
    in
    if builtins.length models > 0 then builtins.head models else null;

  openRouterFreeModels = pkgs.writeShellScriptBin "openrouter-free-models" ''
    ${pkgs.curl}/bin/curl -s "https://openrouter.ai/api/v1/models" \
      | ${pkgs.jq}/bin/jq -r ".data[] | select(.id | endswith(\":free\")) | .id" \
      | fzf
  '';

  prompts = import ./prompt.nix { inherit lib; };
  roles =
    with prompts.chat;
    with prompts.function;
    [
      {
        name = "ShellGPT";
        role = shell.default;
      }
      {
        name = "ShellGPT-Japanese";
        role = withNoThink (toJapanese shell.default);
      }
      {
        name = "Code Generator";
        role = withNoThink (toJapanese shell.codeGenerator);
      }
      {
        name = "Code Refactor";
        role = withNoThink (toJapanese shell.codeRefactor);
      }
      {
        name = "Shell Command Descriptor";
        role = withNoThink (toJapanese shell.shellCommandDescriptor);
      }
      {
        name = "Shell Command Generator";
        role = withNoThink (toJapanese shell.shellCommandGenerator);
      }
      {
        name = "Java Teacher";
        role = withNoThink (toLang "java" "17" shell.codeRefactor);
      }
      {
        name = "Nix Teacher";
        role = withNoThink (toLang "nix" "" shell.codeRefactor);
      }
      {
        name = "Commit Message Generator";
        role = withNoThink (shell.commitMessageGenerator);
      }
      {
        name = "Commit Cleaner";
        role = withNoThink (shell.commitCleaner);
      }
      {
        name = "Requirement Analyst";
        role = withNoThink (toJapanese shell.requirementAnalyst);
      }
    ];

  shellAliases =
    let
      chat = role: "sgpt --no-cache --repl temp --role \"${role}\"";
      stdin = role: "sgpt --no-cache --role \"${role}\"";
    in
    {
      "cmsg" = "git diff --staged | ${stdin "Commit Message Generator"}";

      "chat" = chat "ShellGPT-Japanese";
      "chatcode" = chat "Code Generator";
      "chatshelldesc" = chat "Shell Command Descriptor";
      "chatshellgen" = chat "Shell Command Generator";
      "chatcommitclean" = chat "Commit Cleaner";

      # TODO: generate chat for each language modules
      "chatjava" = chat "Java Teacher";
      "chatnix" = chat "Nix Teacher";
    };

  # Convert existing provider configuration to claude-code-router format
  claudeCodeRouterProviders =
    builtins.map
      (provider:
        let
          # Determine API base URL based on provider type
          apiBaseUrl = "${provider.url}/v1/chat/completions";
        in
        {
          name = provider.name;
          api_base_url = apiBaseUrl;
          api_key = "\${${lib.strings.toUpper provider.name}_API_KEY}"; # dummy
          models = builtins.map (m: m.model) provider.models;
        }
      )
      cfg.providers;

  # Generate claude-code-router config.json content
  claudeCodeRouterConfig = builtins.toJSON {
    LOG = true;
    LOG_LEVEL = "debug";
    API_TIMEOUT_MS = 10000;
    NON_INTERACTIVE_MODE = false;
    Providers = claudeCodeRouterProviders;
    Router = {
      default = let
        chatModel = searchModelByRole "edit";
      in
        if chatModel != null then
          "${chatModel.provider},${chatModel.model}"
        else
          "";
      background = let
        ollamaModels = builtins.filter (p: p.name == "ollama") cfg.providers;
        ollamaModel = if ollamaModels != [] then
          builtins.head (builtins.head ollamaModels).models
        else null;
      in
        if ollamaModel != null then
          "ollama,${ollamaModel.model}"
        else
          "";
      think = let
        editModel = searchModelByRole "chat";
      in
        if editModel != null then
          "${editModel.provider},${editModel.model}"
        else
          "";
    };
  };
in
{
  imports = [
    ./ollama.nix
    ./litellm
  ];

  options.my.home.ai =
    with lib;
    with lib.types;
    {
      enable = mkEnableOption "Enable AI features";
      localOnly = mkEnableOption "Local AI only, not use remote providers";
      providers = mkOption {
        description = "AI provider and model configuration";
        type = listOf (submodule {
          options = {
            name = mkOption {
              description = "Provider and model name";
              type = str;
            };
            url = mkOption {
              description = "Provider URL or model endpoint";
              type = str;
              example = "https://localhost:11434";
            };
            models = mkOption {
              description = "List of models with roles";
              type = listOf (submodule {
                options = {
                  model = mkOption {
                    description = "Model identifier";
                    type = str;
                    example = "gemma3:12b";
                  };
                  modelfileText = mkOption {
                    description = "Model file text content.";
                    type = nullOr str;
                    default = null;
                    example = ''
                      FROM gemma3:12b
                      PARAMETER num_ctx 32768
                    '';
                  };
                  roles = mkOption {
                    description = "Roles for the AI model.";
                    type = listOf (enum [
                      "chat"
                      "edit"
                      "apply"
                      "autocomplete"
                      "embed"
                      "rerank"
                    ]);
                  };
                };
              });
              example = [
                {
                  model = "gemma3:12b";
                  roles = [
                    "chat"
                    "edit"
                    "apply"
                  ];
                }
                {
                  model = "deepseek-coder-v2:16b";
                  roles = [ "autocomplete" ];
                }
              ];
            };
            example = {
              name = "ollama";
              url = "http://localhost:11434";
              models = [
                rec {
                  model = "gemma3:12b";
                  roles = [
                    "chat"
                    "edit"
                    "apply"
                  ];
                }
                rec {
                  model = "deepseek-coder-v2:16b";
                  roles = [ "autocomplete" ];
                }
              ];
            };
          };
        });
      };
    };
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.providers != [ ];
        message = "At least one provider must be specified";
      }
      {
        assertion =
          (
            cfg.localOnly
            &&
              (lib.concatLists (
                map (p: if p.name == "ollama" then map (m: m.model) p.models else [ ]) cfg.providers
              )) != [ ]
          )
          || !cfg.localOnly;
        message = "If localOnly is enabled, at least one ollama model must be specified";
      }
    ];

    programs.vscode.profiles.default = {
      extensions =
        lib.optionals (!cfg.localOnly) (
          pkgs.nix4vscode.forVscode [
            "GitHub.copilot"
            "GitHub.copilot-chat"
            "kilocode.Kilo-Code"
          ]
        );
      userSettings = let
        # Azure Models configuration for GitHub Copilot Chat
        # https://parsiya.net/blog/litellm-ghc-aad/
        azureModelsConfig = (lib.listToAttrs (lib.concatMap (provider:
          lib.map (model:
            lib.nameValuePair "${provider.name}-${model.model}" {
              name = model.model;
              url = "${provider.url}/v1/chat/completions";
              maxInputTokens = -1;
              maxOutputTokens = -1;
              toolCalling = true;
              vision = false;
              thinking = false;
            }
          ) provider.models
        ) cfg.providers)) // { _flattenIgnore = true; };
      in (lib.my.flatten "_flattenIgnore" {
        # The main agent is GitHub Copilot, but it uses only remote models for completions.
        # Thus, use Continue.dev for completion only, and use GitHub Copilot for others.
        # gitlens ai: not work
        gitlens.ai =
          let
            model = searchModelByRole "edit";
          in
          {
            model = "vscode";
            vscode.model = "${model.provider}:${model.model}";
          };
        github.copilot = {
          chat = {
            agent = {
              thinkingTool = true;
            };
            codesearch.enabled = true;
            localeOverride = lib.head (lib.splitString "-" config.my.home.ide.vscode.languages.chat);

            editor.temporalContext.enabled = true;
            edits.temporalContext.enabled = true;

            # Azure models configuration
            azureModels = azureModelsConfig;

            # prompts
            # Refer file to avoid redundant settings.
            # TODO: add ability to add prompts from another modules
            reviewSelection.instructions = [
              {
                "file" = "${config.xdg.configHome}/github-copilot/instructions/Code Refactor.md";
              }
            ];
            commitMessageGeneration.instructions = [
              {
                "file" = "${config.xdg.configHome}/github-copilot/instructions/Commit Message Generator.md";
              }
            ];
          };
        };
        chat = {
          agent.enabled = !cfg.localOnly;
          mcp = {
            enabled = config.my.home.mcp.enable;
            discovery.enabled = false; # conflict: https://github.com/microsoft/vscode/issues/243687#issuecomment-2734934398
          };
        };
        inlineChat = {
          enableV2 = true;
          hideOnRequest = true;
        };
      })
      // {
        mcp = {
          servers = lib.optionalAttrs (builtins.hasAttr "vscode" config.my.home.mcp.serverJsonContents) config.my.home.mcp.serverJsonContents.vscode.mcpServers;
        };
      };
    };

    # For other tools
    # For vscode set "github.copilot.chat.mcp.discovery.enabled" to true.
    home.file.".qwen/settings.json".text = builtins.toJSON (
      {
        preferredEditor = "nvim";
        vimMode = true;
        disableAutoUpdate = true;
        disableUpdateNag = true;
        # selectedAuthType = "oauth-personal"; # only for gemini
        selectedAuthType = "openai"; # only for qwen-coder
        theme = "GitHub";
        checkpointing.enabled = true;
        hideTips = true;
        hideBanner = true;
        enableOpenAILogging = false;
        usageStatisticsEnabled = false;
        telemetry.enabled = false;
      } // lib.optionalAttrs config.my.home.mcp.enable {
        mcpServers = lib.optionalAttrs (builtins.hasAttr "qwen" config.my.home.mcp.serverJsonContents) config.my.home.mcp.serverJsonContents.qwen.mcpServers;
      }
    );
    home.packages = (with pkgs; [
      shell-gpt
      openRouterFreeModels

      # Defined by numtide/nix-ai-tools
      qwen-code'
      opencode

      claude-code
      claude-code-router
    ]);
    programs.bash.shellAliases = shellAliases;
    # shell-gpt needs write permission to .sgptrc .
    home.activation."copy-sgptrc" = ''
      cp ${config.xdg.configHome}/shell_gpt/.sgptrc.orig ${config.xdg.configHome}/shell_gpt/.sgptrc
      chmod u+w ${config.xdg.configHome}/shell_gpt/.sgptrc
    '';
    xdg.configFile =
      let
        shellGptRoles = roles;
        opencodeProvider = providers:
          builtins.listToAttrs (map (p: {
            name = p.name;
            value = {
              npm = "@ai-sdk/openai-compatible";
              name = "${lib.strings.toUpper (lib.strings.substring 0 1 p.name)}${lib.strings.substring 1 (builtins.stringLength p.name - 1) p.name} (local)";
              options.baseURL = "${p.url}/v1";
              models = builtins.listToAttrs (map (m: {
                name = m.model;
                value = {
                  name = m.model;
                };
              }) p.models);
            };
          }) providers);
        opencodeMcp = mcpServers:
          lib.mapAttrs (name: config:
            let
              isRemote = config ? "url";
            in
            {
              type = if isRemote then "remote" else "local";
              enabled = true;
            }
            // (lib.optionalAttrs isRemote { url = config.url; })
            // (lib.optionalAttrs (!isRemote) {
              command = [ config.command ] ++ (config.args or [ ]);
            })
            // (lib.optionalAttrs (config ? "env") { environment = config.env; })
            // (lib.optionalAttrs (config ? "headers") { headers = config.headers; })
          ) mcpServers;
      in {
        "opencode/opencode.json".text = builtins.toJSON (
          {
            "$schema" = "https://opencode.ai/config.json";
            theme = "opencode";
            model = let modelInfo = searchModelByRole "edit"; in "${modelInfo.provider}/${modelInfo.model}";
            provider = opencodeProvider cfg.providers;
          } // lib.optionalAttrs config.my.home.mcp.enable {
              mcp = lib.optionalAttrs (builtins.hasAttr "opencode" config.my.home.mcp.serverJsonContents)
                (opencodeMcp config.my.home.mcp.serverJsonContents.opencode.mcpServers);
          }
        );
      } //
      (
        # shellgpt roles
        builtins.listToAttrs (
          builtins.map (r: {
            name = "shell_gpt/roles/${r.name}.json";
            value.text = builtins.toJSON {
              inherit (r) name role;
            };
          }) shellGptRoles
        )
        // {
          "shell_gpt/.sgptrc.orig".text = lib.my.toSessionVariables (
            let
              modelInfo = searchModelByRole "chat";
              cachePath = "${config.xdg.cacheHome}/shell_gpt";
            in
            rec {
              CHAT_CACHE_PATH = "${cachePath}/cache";
              CACHE_PATH = "${cachePath}/chat-cache";
              CHAT_CACHE_LENGTH = 100;
              CACHE_LENGTH = CHAT_CACHE_LENGTH;
              REQUEST_TIMEOUT = 30;
              DEFAULT_MODEL = modelInfo.model;
              DEFAULT_COLOR = "magenta";
              ROLE_STORAGE_PATH = "${config.xdg.configHome}/shell_gpt/roles";
              SYSTEM_ROLES = false;
              DEFAULT_EXECUTE_SHELL_CMD = false;
              DISABLE_STREAMING = false;
              CODE_THEME = "github-dark";
              API_BASE_URL= modelInfo.url;
              OPENAI_API_KEY = "dummy"; # because use litellm proxy
              USE_LITELLM = false; # to use self-hosted litellm proxy
            }
          );
        }
      )
      // (
        # GitHub Copilot
        builtins.listToAttrs (
          builtins.map (r: {
            name = "github-copilot/instructions/${r.name}.md";
            value.text = r.role;
          }) shellGptRoles
        )
      );

    home.file.".claude-code-router/config.json".text = claudeCodeRouterConfig;

    # Add a custom command to lazygit
    programs.lazygit.settings.customCommands =
      let 
        chatModel = searchModelByRole "chat";
        editModel = searchModelByRole "edit";
      in [
      {
        # Smart commit
        key = "g";
        command = ''bash -c "${pkgs.writeScript "smart-commit" (builtins.readFile ./scripts/smart-commit.sh)} --model ${chatModel.model},${editModel.model}"'';
        description = "Commit by using smart-commit";
        context = "files";
        loadingText = "Committing...";
        output = "terminal";
      }
    ];
  };
}
