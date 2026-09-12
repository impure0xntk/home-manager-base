{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.home.ai;
  defaultPrompts = { };
  defaultAgentsMd = pkgs.writeText "AGENTS.md" (
    (builtins.readFile ./AGENTS.md)
    + (lib.optionalString (cfg.harness.codingAgentTools != { }) ''
      ## Coding Agent Tools

      The following tools are available exclusively inside coding agent wrappers.
      They are automatically injected into the agent's environment.

      ${lib.concatStringsSep "\n\n" (
        lib.mapAttrsToList (
          name: tool:
          lib.optionalString (tool.prompt != "") ''
            ${tool.prompt}
          ''
        ) cfg.harness.codingAgentTools
      )}
    '')
  );
in
{
  options.my.home.ai.harness =
    with lib;
    with lib.types;
    {
      prompts = mkOption {
        description = "Prompt files to install into the prompts directory.";
        type = attrsOf (submodule {
          options = {
            text = mkOption {
              type = str;
              default = "";
              description = "The prompt content as text.";
            };
            source = mkOption {
              type = nullOr path;
              default = null;
              description = "Path to a file containing the prompt content.";
            };
          };
        });
        default = defaultPrompts;
      };

      agentsMd = mkOption {
        description = "AGENTS.md file to install.";
        type = submodule {
          options = {
            text = mkOption {
              type = str;
              default = "";
              description = "The AGENTS.md content as text.";
            };
            source = mkOption {
              type = nullOr path;
              default = null;
              description = "Path to a file containing the AGENTS.md content.";
            };
          };
        };
        default = {
          source = defaultAgentsMd;
        };
      };
    };

  config = lib.mkIf cfg.harness.enable {
    xdg.configFile = lib.mkMerge [
      (lib.mapAttrs' (name: prompt: {
        name = "ai/prompts/${name}";
        value = {
          source = prompt.source or (pkgs.writeText "${name}" prompt.text);
        };
      }) cfg.harness.prompts)
      (lib.optionalAttrs (cfg.harness.agentsMd.source != null || cfg.harness.agentsMd.text != "") {
        "ai/AGENTS.md" = {
          source = cfg.harness.agentsMd.source or (pkgs.writeText "AGENTS.md" cfg.harness.agentsMd.text);
        };
      })
    ];
  };
}
