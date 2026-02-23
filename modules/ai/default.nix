{
  config,
  lib,
  pkgs,
  ...
}@args:
let
  cfg = config.my.home.ai;
in
{
  imports = [
    ./prompt.nix
    ./ollama.nix
    ./skills.nix

    # CLI agents module
    ./agents
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

          "johnny-zhao.oai-compatible-copilot" # instead of BYOK
        ]
      );
      userSettings =
        let
          oaiCompatibleFirstProvider = builtins.head config.my.home.ai.providers;
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
            baseUrl = "${oaiCompatibleFirstProvider.url}/v1";
            models = oaiCompatibleModelsConfig;
          };
          # The main agent is GitHub Copilot, but it uses only remote models for completions.
          # Thus, use Continue.dev for completion only, and use GitHub Copilot for others.
          github.copilot = {
            chat = {
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
            useAgentSkills = true;
            customAgentInSubagent.enabled = true;
            commandCenter.enabled = false; # disabled title bar icon
            mcp = lib.optionalAttrs config.my.home.mcp.hub.client.enable {
              access = "all";
              discovery.enabled = { # conflict: https://github.com/microsoft/vscode/issues/243687#issuecomment-2734934398
                "claude-desktop" = false;
                "windsurf" = false;
                "cursor-global" = false;
                "cursor-workspace" = false;
                _flattenIgnore = true;
              };
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
