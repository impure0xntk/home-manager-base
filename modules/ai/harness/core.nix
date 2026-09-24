{ config, pkgs, lib, ... }:
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

      pluginDir = mkOption {
        type = path;
        default = "${config.home.homeDirectory}/.agents/plugins";
        readOnly = true;
        description = "Target directory for installed plugin files";
      };

      pluginPackages = mkOption {
        type = attrsOf package;
        default = {};
        description = "Packages to install as plugins for the harness";
      };
    };
  config = lib.mkIf config.my.home.ai.harness.enable {
    my.home.ai.harness.plugins = {
      "nixos-reactor-harness-for-all-agents" = {
        "plugin.json" = {
          # No "$schema": codex loads plugin hooks only for legacy-format
          # manifests (loader.rs skips hooks when the manifest declares
          # the agent-plugins schema).
          name = "nixos-reactor-harness-for-all-agents";
          version = "1.0.0";
          description = "NixOS Reactor Harness Plugin for all agents.";
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
            Stop = [
              { hooks = [
                {
                  type = "command";
                  command = "${pkgs.libnotify}/bin/notify-send --category \"Agent\" --expire-time 10 \"Task completed.\"";
                  timeout = 10;
                }
              ]; }
            ];
          };
        };
      };
    };
  };
}
