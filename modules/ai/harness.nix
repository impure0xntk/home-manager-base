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
      includes = [ "mcp-builder" "doc-coauthoring" "docx" "pdf" "pptx" "xlsx" ];
      excludes = [ ];
    };
    obra-superpowers = {
      url = "https://github.com/obra/superpowers.git";
      revision = "b36e0829c6d0140e93cfef2ca599b1b07d4a7797";
      hash = "sha256-EsGNO0dULWf5Bx6bGrCv2kI2Z8aKH0kRvGiuN23wChQ=";
      description = "Obra's superpowers skill set";
      includes = [ ];
      excludes = [ ];
    };
    awesome-copilot = {
      url = "https://github.com/github/awesome-copilot.git";
      revision = "7568a482ce2df38f8965ab5336a3220db796a4ba";
      hash = "sha256-wMNloxg/mKRu6yr6pj1crdk08D+wTv/kjIcjrkHriw8=";
      description = "GitHub Copilot community resources";
      includes = [ "acquire-codebase-knowledge" "agent.*" "autoresearch" "conventional.*" "create-specification" "create-readme" "create-tldr-page" ];
      excludes = [ ];
    };
  };

  defaultPrompts = { };

  defaultAgentsMd = pkgs.writeText "AGENTS.md" (
    (builtins.readFile ./prompts/AGENTS.md)
    + ''
      ## Installed Skills

      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: path: ''
        - **${name}**: ${cfg.harness.skills.${name}.description}
          - Source: `${path}`
      '') skillDerivationSet)}
    ''
  );

  matchPatterns = patterns: name:
    lib.any (pattern: builtins.match ("^" + pattern + "$") name != null) patterns;

  # Filter skills based on includes/excludes options using regex patterns
  # Output structure: flat directory with repoName-skillName
  filterSkills = name: value: src:
    let
      # Get skill names from the skills/ subdirectory or root
      skillsSubDir = "${src}/skills";
      skillNames = if builtins.pathExists skillsSubDir
        then builtins.attrNames (builtins.readDir skillsSubDir)
        else builtins.attrNames (builtins.readDir src);

      filteredNames = lib.filter (skillName:
        let
          inIncludes = value.includes == [ ] || matchPatterns value.includes skillName;
          inExcludes = matchPatterns value.excludes skillName;
        in
          inIncludes && !inExcludes
      ) skillNames;
    in
    pkgs.runCommand "${name}-filtered" { } ''
      mkdir -p $out
      # Copy filtered skills from skills/ subdirectory if it exists
      if [ -d ${src}/skills ]; then
        for skill in ${lib.concatStringsSep " " filteredNames}; do
          cp -r ${src}/skills/$skill $out/${name}-$skill 2>/dev/null || true
        done
      else
        # Otherwise copy from root
        for skill in ${lib.concatStringsSep " " filteredNames}; do
          cp -r ${src}/$skill $out/${name}-$skill 2>/dev/null || true
        done
      fi
    '';

  # Fetch and filter skills
  skillDerivationSet = lib.mapAttrs (name: value:
    let
      fetched = pkgs.fetchgit {
        inherit (value) url;
        rev = value.revision;
        sha256 = value.hash;
      };
    in
    filterSkills name value fetched
  ) cfg.harness.skills;

  # Flatten all skills into individual entries for xdg.configFile
  # Each skill gets its own symlink directly under ai/skills/
  # Map each repo's output to individual skill entries, then merge all
  repoSkills = lib.mapAttrs (repoName: repoPath:
    let
      skillDirs = builtins.attrNames (builtins.readDir repoPath);
    in
    lib.listToAttrs (lib.map (skillName: {
      name = skillName;
      value = { source = "${repoPath}/${skillName}"; };
    }) skillDirs)
  ) skillDerivationSet;

  flatSkills = builtins.foldl' (acc: skills: acc // skills) { } (builtins.attrValues repoSkills);
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
          includes = mkOption {
            type = listOf str;
            default = [ ];
            description = ''
              List of regex patterns to include from the repository.
              If empty, all skills are included (subject to excludes).
              Patterns are anchored (^pattern$) for full string matching.
              Examples:
                includes = [ "claude-api" "doc-coauthoring" ];  # exact match
                includes = [ "agent.*" "conventional.*" "create-.*" ];  # regex patterns
            '';
          };
          excludes = mkOption {
            type = listOf str;
            default = [ ];
            description = ''
              List of regex patterns to exclude from the repository.
              Patterns are anchored (^pattern$) for full string matching.
              Examples:
                excludes = [ "brand-guidelines" "canvas-design" ];  # exact match
                excludes = [ ".*-deprecated" "test-.*" ];           # regex patterns
            '';
          };
        };
      });
      default = defaultSkillRepos;
    };

    prompts = mkOption {
      description = ''
        Prompt files to install into the prompts directory.

        Each prompt can have either:
        - `text`: The prompt content as a string
        - `source`: Path to a file containing the prompt content

        Example:
        ```nix
        my-home.ai.harness.prompts.my-prompt = {
          text = "You are a helpful assistant...";
        };
        # or
        my-home.ai.harness.prompts.my-prompt = {
          source = ./my-prompt.md;
        };
        ```
      '';
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
      description = ''
        AGENTS.md file to install.

        Can have either:
        - `text`: The AGENTS.md content as a string
        - `source`: Path to a file containing the AGENTS.md content

        Example:
        ```nix
        my-home.ai.harness.agentsMd = {
          text = "# AGENTS.md\n\nRules for AI agents...";
        };
        # or
        my-home.ai.harness.agentsMd = {
          source = ./AGENTS.md;
        };
        ```
      '';
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

  config = lib.mkIf cfg.harness.enable {
    home.packages = with pkgs; [
      rtk
    ];

    xdg.configFile = lib.mkMerge [
      (lib.mapAttrs' (name: entry: {
        name = "ai/skills/${name}";
        value = entry;
      }) flatSkills)
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
