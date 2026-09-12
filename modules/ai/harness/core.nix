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
}
