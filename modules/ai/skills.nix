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
  options.my.home.ai.openskills = {
    enable = lib.mkEnableOption "Enable OpenSkills configuration for AI agents.";

    # Skills to install with detailed configuration
    skills = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          repo = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            description = "List of GitHub repos (e.g., 'anthropics/skills') or local paths (e.g., './local-skills/my-skill') to install";
            example = [ "anthropics/skills" "custom/skill" ];
          };
          path = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Custom installation path (null for default: ~/.agent/skills or ./.agent/skills)";
            example = "~/.custom-skills";
          };
          global = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Install globally (true) or locally (false)";
          };
          universal = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Install in universal format for broader compatibility";
          };
        };
      });
      default = [
        { repo = [ "anthropics/skills" ]; global = true; universal = true; path = "~/"; }
      ];
      description = "List of skill configurations to install";
      example = [
        { repo = [ "anthropics/skills" ]; global = true; universal = true; }
        { repo = [ "custom/skill" "another/skill" ]; path = "~/.my-skills"; global = true; universal = false; }
        { repo = [ "./local-skills/dev-skill" ]; global = false; universal = true; }
      ];
    };

    agentsMdPath = lib.mkOption {
      type = lib.types.str;
      default = "${config.xdg.configHome}/ai/AGENTS-Skills.md";
      description = "Path to sync OpenSkills AGENTS.md file for documentation.";
    };
  };

  config = lib.mkIf cfg.openskills.enable {
    # Install OpenSkills from nix-ai-tools (llm-agents.nix)
    home.packages = with pkgs; [
      openskills
    ];

    # Activation script to install skills with per-skill configuration
    home.activation.installOpenSkills = lib.hm.dag.entryAfter ["writeBoundary"] ''
      # Set PATH to include OpenSkills and git
      export PATH="$PATH:${lib.makeBinPath [pkgs.openskills pkgs.git]}"

      ${lib.concatMapStrings (skill:
        let
          # Determine installation path
          installPath = if skill.path == null then "" else skill.path;

          # Build install flags
          installFlags = lib.strings.concatStringsSep " " (
            lib.optional skill.global "--global" ++
            lib.optional skill.universal "--universal"
          );
        in ''
          SKILL_PATH="${installPath}"
          INSTALL_FLAGS="${installFlags}"

          # Create directory if it doesn't exist
          if test -n "$SKILL_PATH"; then
            mkdir -p "$SKILL_PATH"
            pushd "$SKILL_PATH"
            echo "Installing OpenSkills to $SKILL_PATH"
          fi
          ${lib.concatMapStrings (repo:
            let
              repoName = lib.strings.escapeShellArg (builtins.baseNameOf repo);
            in ''
              SKILL_REPO_NAME="${repoName}"
              openskills install ${lib.strings.escapeShellArg repo} $INSTALL_FLAGS -y || echo "Warning: Failed to install ${lib.strings.escapeShellArg repo}"
            ''
          ) skill.repo}
        ''
      ) cfg.openskills.skills}

      # Sync AGENTS.md to ensure it's up-to-date
      echo "Syncing AGENTS.md with OpenSkills..."
      openskills sync -y --output "${cfg.openskills.agentsMdPath}" || echo "Warning: Failed to sync AGENTS.md"
    '';

    # TODO: don't use lib.mkForce
    my.home.ai.prompts.instructions."AGENTS.md".text = lib.mkForce (config.my.home.ai.prompts.presets.instructions."AGENTS.md".text + ''
    ## Skills

    - See ${cfg.openskills.agentsMdPath} for details.
    ''); # sync with prompts module
  };
}
