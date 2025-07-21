{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.home.ai;

  model = rec {
    default = light;
    light = "openrouter/google/gemma-3-27b-it:free";
  };

  ollomaModels = lib.concatLists (
    map (p: if p.name == "ollama" then p.models else [ ]) cfg.providers
  );
  hasOllamaModel = builtins.length ollomaModels > 0;
  ollomaProvider = lib.findFirst (p: p.name == "ollama") { url = ""; } cfg.providers;

  # Map to include provider URL and apiKey along with the model
  # expected result format:
  # [
  #   {
  #     provider = "ollama";
  #     url = "http://localhost:11434";
  #     apiKey = "dummy-api-key";
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
              inherit (provider) url apiKey;
              inherit (m_) model roles;
              provider = provider.name;
            }) provider.models
          )
        ) cfg.providers
      );
    in
    if builtins.length models > 0 then builtins.head models else null;

  shell-gpt-openrouter = pkgs.writeShellScriptBin "sgpt" ''
    API_BASE_URL=https://openrouter.ai/api/v1 \
    OPENAI_API_KEY=''${OPENROUTER_API_KEY:-} \
    ${pkgs.shell-gpt}/bin/sgpt "$@"
  '';
  shell-gpt-light = pkgs.writeShellScriptBin "sgpt-light" ''
    ${shell-gpt-openrouter}/bin/sgpt --model ${model.light} "$@"
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
    ];

  shellAliases =
    let
      chat = role: "sgpt-light --no-cache --repl temp --role \"${role}\"";
      stdin = role: "sgpt-light --no-cache --role \"${role}\"";
    in
    {
      "cmsg" = "git diff --staged | ${stdin "Commit Message Generator"}";

      "chat" = chat "ShellGPT-Japanese";
      "chatcode" = chat "Code Generator";
      "chatshelldesc" = chat "Shell Command Descriptor";
      "chatshellgen" = chat "Shell Command Generator";

      # TODO: generate chat for each language modules
      "chatjava" = chat "Java Teacher";
      "chatnix" = chat "Nix Teacher";
    };
in
{
  imports = [
    ./mcp
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
            apiKey = mkOption {
              description = "API key for the provider";
              type = str;
              default = "";
            };
            models = mkOption {
              description = "List of models with roles";
              type = listOf (submodule {
                options = {
                  name = mkOption {
                    description = "Model name";
                    type = str;
                    example = "gemma";
                  };
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
                  name = "gemma3";
                  model = "gemma3:12b";
                  roles = [
                    "chat"
                    "edit"
                    "apply"
                  ];
                }
                {
                  name = "deepseek-coder";
                  model = "deepseek-coder-v2:16b";
                  roles = [ "autocomplete" ];
                }
              ];
            };
            example = {
              name = "ollama";
              url = "http://localhost:11434";
              apiKey = "your-api-key-here";
              models = [
                rec {
                  name = "gemma3:12b";
                  model = name;
                  roles = [
                    "chat"
                    "edit"
                    "apply"
                  ];
                }
                rec {
                  name = "deepseek-coder-v2:16b";
                  model = name;
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
      (
        let
          remoteProviders = lib.filter (
            p: !(lib.hasInfix "localhost" p.url) && !(lib.hasInfix "127.0.0.1" p.url)
          ) cfg.providers;
        in
        {
          assertion = lib.all (p: p.apiKey != null) remoteProviders;
          message = "All remote providers must have an apiKey";
        }
      )
    ];

    programs.vscode.profiles.default = {
      extensions =
        pkgs.nix4vscode.forVscode [
          "continue.continue"
        ]
        ++ (lib.optionals (!cfg.localOnly) (
          pkgs.nix4vscode.forVscode [
            "GitHub.copilot"
            "GitHub.copilot-chat"
            "CodeRabbit.coderabbit-vscode"
          ]
        ));
      userSettings =
        (lib.my.flatten "_flattenIgnore" {
          # The main agent is GitHub Copilot, but it uses only remote models for completions.
          # Thus, use Continue.dev for completion only, and use GitHub Copilot for others.
          continue = {
            enableTabAutocomplete = true;
            telemetryEnabled = false;
          };
          # gitlens ai: not work
          gitlens.ai =
            let
              model = searchModelByRole "edit";
            in
            {
              model = "vscode";
              vscode.model = "${model.provider}:${model.model}";
              ollama.url = ollomaProvider.url;
            };
          github.copilot = {
            chat = {
              byok.ollamaEndpoint = lib.optionalAttrs hasOllamaModel ollomaProvider.url;
              agent = {
                thinkingTool = true;
              };
              localeOverride = lib.head (lib.splitString "-" config.my.home.ide.vscode.languages.chat);

              editor.temporalContext.enabled = true;
              edits.temporalContext.enabled = true;

              # prompts
              # Refer file to avoid redundant settings.
              # TODO: add ability to add prompts from another modules
              codeGeneration.instructions = [
                {
                  "file" = "${config.xdg.configHome}/github-copilot/instructions/Code Generator.md";
                }
              ];
              testGeneration.instructions = [
                {
                  "file" = "${config.xdg.configHome}/github-copilot/instructions/Code Generator.md";
                }
              ];
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
              enabled = true;
              discovery.enabled = false; # conflict: https://github.com/microsoft/vscode/issues/243687#issuecomment-2734934398
            };
          };
        })
        // {
          mcp = {
            servers = cfg.mcp.servers;
          };
        };
    };

    # For other tools
    # For vscode set "github.copilot.chat.mcp.discovery.enabled" to true.
    home.file.".gemini/settings.json".text = builtins.toJSON {
      selectedAuthType = "oauth-personal";
      theme = "GitHub";
      preferredEditor = "vscode";
      mcpServers = cfg.mcp.servers;
    };
    home.file.".continue/config.yaml".source = lib.my.toYaml {
      name = "Local Assistant";
      version = "1.0.0";
      schema = "v1";
      models = lib.flatten (
        lib.concatMap (
          v:
          (map (m: {
            name = m.name;
            provider = v.name;
            model = m.model;
            roles = m.roles;
            apiBase = v.url;
            apiKey = v.apiKey;
          }) v.models)
        ) cfg.providers
      );
      context = [
        { provider = "code"; }
        { provider = "docs"; }
        { provider = "diff"; }
        { provider = "terminal"; }
        { provider = "problems"; }
        { provider = "folder"; }
        { provider = "codebase"; }
      ];
    };

    services.ollama = {
      enable = hasOllamaModel;
      acceleration = "cuda";
      environmentVariables =
        {
          # https://github.com/ollama/ollama/issues/8597#issuecomment-2614533288

          # Change models path
          OLLAMA_MODELS = "${config.xdg.dataHome}/ollama/models";

          HIP_VISIBLE_DEVICES = "0,1";

          OLLAMA_NUM_PARALLEL = "1";
          OLLAMA_KEEP_ALIVE = "1h";
        }
        //
        # https://blog.peddals.com/ollama-vram-fine-tune-with-kv-cache/
        (
          if lib.any (m: lib.hasInfix "gemma3" m.model) ollomaModels then
            {
              # For gemma3
              OLLAMA_FLUSH_ATTENTION = "0";
              OLLAMA_KV_CACHE_TYPE = "f16";
            }
          else
            {
              # General
              OLLAMA_FLUSH_ATTENTION = "1";
              OLLAMA_KV_CACHE_TYPE = "q8_0";
            }
        );
    };

    systemd.user.services.ollama-pull-models =
      let
        package = config.services.ollama.package;
        originalModelIds = map (m: m.model) (lib.filter (m: m.modelfileText == null) ollomaModels);
        customModelFiles = map (m: {
          modelId = m.model;
          modelfile = pkgs.writeText "Modelfile.${m.model}" m.modelfileText;
        }) (lib.filter (m: m.modelfileText != null) ollomaModels);

        pullScript = pkgs.writeShellScript "ollama-pull-models" (
          ''
            for model in ${lib.concatStringsSep " " originalModelIds}; do
              ${package}/bin/ollama pull "$model"
            done
          ''
          + lib.concatStringsSep "\n" (
            lib.forEach customModelFiles (m: ''
              ${package}/bin/ollama create ${m.modelId} -f ${m.modelfile}
              ${package}/bin/ollama run "${m.modelId}"
            '')
          )
        );
      in
      lib.mkIf hasOllamaModel {
        Unit = {
          Description = "Server for local large language models";
          # depends ollama.service. see https://github.com/nix-community/home-manager/blob/master/modules/services/ollama.nix
          Requires = [ "ollama" ];
          After = [ "ollama" ];
        };

        Service.ExecStart = pullScript;

        Install = {
          WantedBy = [ "default.target" ];
        };
      };

    # shellgpt
    home.packages = with pkgs; [
      gemini-cli-static # for gemini
      llxprt-code-static # for openrouter
      
      shell-gpt-openrouter
      shell-gpt-light
    ];
    programs.bash.shellAliases = shellAliases;
    # shell-gpt needs write permission to .sgptrc .
    home.activation."copy-sgptrc" = ''
      cp ${config.xdg.configHome}/shell_gpt/.sgptrc.orig ${config.xdg.configHome}/shell_gpt/.sgptrc
      chmod u+w ${config.xdg.configHome}/shell_gpt/.sgptrc
    '';
    xdg.configFile =
      let
        # result = searchModelByRole "chat";
        result = searchModelByRole "edit"; # to avoid waiting for chat model to be ready.
        shellGptRoles = roles;
      in
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
              cachePath = "${config.xdg.cacheHome}/shell_gpt";
            in
            rec {
              CHAT_CACHE_PATH = "${cachePath}/cache";
              CACHE_PATH = "${cachePath}/chat-cache";
              CHAT_CACHE_LENGTH = 100;
              CACHE_LENGTH = CHAT_CACHE_LENGTH;
              REQUEST_TIMEOUT = 30;
              DEFAULT_MODEL = model.default; # LiteLLM format
              DEFAULT_COLOR = "magenta";
              ROLE_STORAGE_PATH = "${config.xdg.configHome}/shell_gpt/roles";
              SYSTEM_ROLES = false;
              DEFAULT_EXECUTE_SHELL_CMD = false;
              DISABLE_STREAMING = false;
              CODE_THEME = "github-dark";
              USE_LITELLM = true;
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

    # Add a custom command to lazygit
    programs.lazygit.settings.customCommands = [
      {
        # Smart commit
        key = "g";
        command = pkgs.writeScript "smart-commit" (builtins.readFile ./scripts/smart-commit.sh);
        description = "Commit by using smart-commit";
        context = "files";
        loadingText = "Committing...";
        output = "terminal";
      }
    ];
  };
}
