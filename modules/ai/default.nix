{
  config,
  lib,
  pkgs,
  ...
}@args:
let
  cfg = config.my.home.ai;

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
in
{
  imports = [
    ./prompt.nix
    ./ollama.nix
    ./litellm
    # (import ./codex.nix (args // {inherit searchModelByRole;}))
    (import ./opencode.nix (args // { inherit searchModelByRole; }))
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
      extensions = lib.optionals (!cfg.localOnly) (
        pkgs.nix4vscode.forVscode [
          "GitHub.copilot"
          "GitHub.copilot-chat"
          "kilocode.Kilo-Code"

          "johnny-zhao.oai-compatible-copilot" # instead of BYOK
        ]
      );
      userSettings =
        let
          oaiCompatibleModelsConfig = lib.flatten (
            lib.forEach cfg.providers (
              provider:
              lib.forEach provider.models (model: {
                id = model.model;
                owned_by = "litellm";
                vision = false;
                reasoning = {
                  effort = "auto";
                };
                _flattenIgnore = true;
              })
            )
          );
        in
        (lib.my.flatten "_flattenIgnore" {
          oaicopilot = {
            # TODO: baseurl selection
            baseUrl = "http://localhost:${builtins.toString config.my.home.ai.litellm.port}/v1";
            models = oaiCompatibleModelsConfig;
          };
          # The main agent is GitHub Copilot, but it uses only remote models for completions.
          # Thus, use Continue.dev for completion only, and use GitHub Copilot for others.
          github.copilot = {
            chat = {
              agent = {
                thinkingTool = true;
              };
              codesearch.enabled = true;
              localeOverride = lib.head (lib.splitString "-" config.my.home.ide.vscode.languages.chat);

              editor.temporalContext.enabled = true;
              edits.temporalContext.enabled = true;

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
            agentSessionsViewLocation = "view";
            commandCenter.enabled = false; # disabled title bar icon
            mcp = {
              enabled = config.my.home.mcp.hub.client.enable;
              discovery.enabled = false; # conflict: https://github.com/microsoft/vscode/issues/243687#issuecomment-2734934398
            };
            promptFilesLocations = {
              "${config.my.home.ai.prompts.baseDir}/instructions" = true;
              _flattenIgnore = true;
            };
          };
          inlineChat = {
            enableV2 = true;
            hideOnRequest = true;
          };
        })
        // {
          mcp = {
            servers = lib.optionalAttrs config.my.home.mcp.hub.client.enable {
              vscode = {
                command = "mcp-remote-group-primary";
                args = [ "vscode" ];
              };
            };
          };
        };
    };
   };
}
