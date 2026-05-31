{
  config,
  pkgs,
  lib,
  ...
}:
let
  # To set AGENTS.md content to default and pin it.
  # If remove this to default or config, this cannot be refer in other modules.
  presets = {
    instructions = {
      "AGENTS.md".source = ./AGENTS.md;
    };
    prompts = {};
  };
in
{
  options.my.home.ai.prompts = {
    instructions = lib.mkOption {
      type =
        with lib.types;
        attrsOf (
          submodule (
            { name, ... }:
            {
              options = {
                text = lib.mkOption {
                  type = lib.types.str;
                  description = "The instruction content as text.";
                };
                source = lib.mkOption {
                  type = lib.types.path;
                  description = "Path to a file containing the instruction content.";
                };
              };
            }
          )
        );
      default = presets.instructions;
      description = "Abstract instruction prompts for AI assistants, with VS Code as base.";
    };

    prompts = lib.mkOption {
      type =
        with lib.types;
        attrsOf (
          submodule (
            { name, ... }:
            {
              options = {
                text = lib.mkOption {
                  type = lib.types.str;
                  description = "The prompt content as text.";
                };
                source = lib.mkOption {
                  type = lib.types.path;
                  description = "Path to a file containing the prompt content.";
                };
              };
            }
          )
        );
      default = presets.prompts;
      description = "Specific prompts for AI assistants, with VS Code as base.";
    };

    baseDir = lib.mkOption {
      type = lib.types.path;
      description = "Base directory for prompt files.";
      default = "${config.xdg.configHome}/ai";
      readOnly = true;
    };

    snippets = lib.mkOption {
      type = with lib.types; attrsOf unspecified;
      default = { };
      description = "Legacy snippets option. Use 'instructions' and 'prompts' instead.";
    };

    presets = lib.mkOption {
      type = lib.types.attrs;
      default = presets;
      description = "Presets of ai prompts. Read-only";
    };
  };
  config = lib.mkIf (config.my.home.ai.enable) {
    xdg.configFile = lib.mkMerge [
      (lib.mapAttrs' (name: instruction: {
        name = "ai/instructions/${name}";
        value = {
          source = instruction.source;
        };
      }) config.my.home.ai.prompts.instructions)

      (lib.mapAttrs' (name: prompt: {
        name = "ai/prompts/${name}";
        value = {
          source = prompt.source;
        };
      }) config.my.home.ai.prompts.prompts)
    ];
  };
}
