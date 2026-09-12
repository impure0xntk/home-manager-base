{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.home.ai;

  # Default skill repos with pinned revisions for supply chain security.
  # Each entry specifies a git URL + a specific revision (commit SHA or tag).
  # If revision is null, the skill is not pinned (use with caution).
  defaultSkillRepos = {
    anthropics-skills = {
      url = "https://github.com/anthropics/skills.git";
      revision = "34040c9c568585f6929bedeaad110ad08f079624"; # e.g. "abc123def456..." — set to pin
      hash = "sha256-tI4bTTBfI1ylltklGyiyA7pLoKXEWtrT6lrmwrpLbCw=";
      description = "Anthropic official skills";
    };
    obra-superpowers = {
      url = "https://github.com/obra/superpowers.git";
      revision = "b36e0829c6d0140e93cfef2ca599b1b07d4a7797";
      hash = "sha256-EsGNO0dULWf5Bx6bGrCv2kI2Z8aKH0kRvGiuN23wChQ=";
      description = "Obra's superpowers skill set";
    };
    awesome-copilot = {
      url = "https://github.com/github/awesome-copilot.git";
      revision = "7568a482ce2df38f8965ab5336a3220db796a4ba";
      hash = "sha256-wMNloxg/mKRu6yr6pj1crdk08D+wTv/kjIcjrkHriw8=";
      description = "GitHub Copilot community resources";
    };
  };

  # Build a nix fetchurl/fetchgit for pinned skills to get their hash
  # This ensures the content matches what we expect
  skillDerivations = lib.mapAttrsToList (name: skill:
  {
    "${name}" = pkgs.fetchgit {
      inherit (skill) url;
      rev = skill.revision;
      sha256 = skill.hash;
    };
  }) cfg.harness.skills;
in
{
  options.my.home.ai.harness = with lib; with lib.types; {
    enable = mkEnableOption "Enable Nix-native AI skill/prompt distribution (replaces openskills)";

    skills = mkOption {
      description = ''
        Skill repositories to clone/symlink into the skills directory.

        Each skill can be:
        - A git URL with an optional revision (commit SHA or tag) for pinning
        - A local absolute path (starting with /)

        **Security**: Always set `revision` to a specific commit SHA for remote
        repos. This prevents supply chain attacks where a malicious commit
        could inject harmful instructions into your AI agent's context.

        Example:
        ```nix
        my-home.ai.harness.skills.my-skill = {
          url = "https://github.com/org/skill-repo.git";
          revision = "abc123def456789...";  # Pin to exact commit
          description = "My custom skill";
        };
        ```
      '';
      type = attrsOf (submodule {
        options = {
          url = mkOption {
            type = str;
            description = "Git URL (https:// or git://) or absolute local path (starting with /)";
            example = "https://github.com/anthropics/skills.git";
          };
          revision = mkOption {
            type = nullOr str;
            default = null;
            description = ''
              Git revision (commit SHA or tag) to pin this skill to.
              **Strongly recommended** for remote repos to prevent supply chain attacks.
              If null, the latest HEAD will be fetched (unpinned, less secure).
            '';
          };
          hash = mkOption {
            type = nullOr str;
            default = null;
            description = ''
              Optional SHA-256 hash of the fetched content for additional integrity verification.
              If provided, Nix will verify the fetched content matches this hash.
              Use `nix-prefetch-git <url> --rev <revision>` to obtain.
            '';
          };
          description = mkOption {
            type = str;
            default = "";
            description = "Human-readable description of this skill";
          };
        };
      });
      default = defaultSkillRepos;
    };

    skillsDir = mkOption {
      type = path;
      default = "${config.xdg.configHome}/ai/skills";
      readOnly = true;
      description = "Target directory for installed skill symlinks / clones";
    };

    agentsMdPath = mkOption {
      type = path;
      default = "${config.xdg.configHome}/ai/AGENTS-Skills.md";
      description = "Path to generated AGENTS.md referencing installed skills";
    };

  };

  config = lib.mkIf cfg.harness.enable {
    home.packages = with pkgs; [
      rtk
    ];

    # Write AGENTS.md listing installed skills with their pin status
    my.home.ai.prompts.instructions = lib.mkMerge [
      {
        "AGENTS.md".source = ./prompts/AGENTS.md;
      }
      {
        "AGENTS-Skills.md".source = pkgs.writeText "AGENTS-Skills.md" ''
          ## Installed Skills

          ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: skill: ''
            - **${name}**: ${skill.description}
              - Source: `${skill.url}`
              - Pinned: ${if skill.revision != null then "${skill.revision}" else "UNPINNED (security risk)"}
          '') cfg.harness.skills)}

          Skills directory: `${cfg.harness.skillsDir}`
        '';
      }
    ];

    xdg.configFile = lib.mkMerge (
      map (item:
        builtins.listToAttrs (map (name: {
          name = "ai/skills/${name}";
          value = { source = item.${name}; };
        }) (builtins.attrNames item))
      ) skillDerivations
    );
  };
}
