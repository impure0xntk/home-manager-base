{ config, lib, ... }:
{
  options.my.home.ai.harness =
    with lib;
    with lib.types;
    {
      enable = mkEnableOption "Enable Nix-native AI skill/prompt distribution (replaces openskills)";

      skillsDir = mkOption {
        type = path;
        default = "${config.xdg.configHome}/ai/skills";
        readOnly = true;
        description = "Target directory for installed skill symlinks / clones";
      };

      promptsDir = mkOption {
        type = path;
        default = "${config.xdg.configHome}/ai/prompts";
        readOnly = true;
        description = "Target directory for installed prompt files";
      };
    };
  config = lib.mkIf config.my.home.ai.harness.enable {
    my.home.ai.harness.plugins = {
      "nixos-reactor-harness" = {
        "plugin.json" = {
          name = "nixos-reactor-harness";
          version = "1.0.0";
          description = "NixOS Reactor Harness Plugin.";
        };
        "hooks/hooks.json" = {
          hooks = {
            SessionStart = [
              { hooks = [
                {
                  type = "command";
                  command = "${config.my.home.ai.harness.codingAgentTools.codegraph.package}/bin/codegraph sync --quiet || true";
                  timeout = 30;
                }
              ]; }
            ];
            UserPromptSubmit = [
              { hooks = [
                {
                  type = "command";
                  command = "${config.my.home.ai.harness.codingAgentTools.codegraph.package}/bin/codegraph prompt-hook || true";
                  timeout = 30;
                }
              ]; }
            ];
          };
        };
      };
    };
  };
}
