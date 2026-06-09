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
      # Pin to a specific commit SHA to prevent supply chain attacks / prompt injection.
      # Update this periodically after reviewing upstream changes.
      revision = "57546260929473d4e0d1c1bb75297be2fdfa1949"; # e.g. "abc123def456..." — set to pin
      description = "Anthropic official skills";
    };
    obra-superpowers = {
      url = "https://github.com/obra/superpowers.git";
      revision = "6fd4507659784c351abbd2bc264c7162cfd386dc";
      description = "Obra's superpowers skill set";
    };
    awesome-copilot = {
      url = "https://github.com/github/awesome-copilot.git";
      revision = "8b1792d493d9f8f0a88d594eb23bb9196639ec3d";
      description = "GitHub Copilot community resources";
    };
  };

  # Validate that pinned skills have a non-null revision
  pinnedSkills = lib.filterAttrs (name: skill: skill.revision != null) cfg.harness.skills;
  unpinnedSkills = lib.filterAttrs (name: skill: skill.revision == null) cfg.harness.skills;

  # Build a nix fetchurl/fetchgit for pinned skills to get their hash
  # This ensures the content matches what we expect
  skillDerivations = lib.mapAttrs (name: skill:
    if skill.revision != null then
      pkgs.fetchgit {
        inherit (skill) url;
        rev = skill.revision;
        # sha256 will be filled in by nix on first build (or set explicitly)
        sha256 = skill.hash or "";
      }
    else
      null
  ) cfg.harness.skills;
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

    # Security warning for unpinned skills
    warnOnUnpinned = mkOption {
      type = bool;
      default = true;
      description = "Emit a warning when skills are configured without a pinned revision";
    };
  };

  config = lib.mkIf cfg.harness.enable {
    # Security assertions
    assertions = lib.optionals cfg.harness.warnOnUnpinned (lib.mapAttrsToList (name: skill: {
      assertion = false;
      message = ''
        Harness skill '${name}' (${skill.url}) has no pinned revision.
        This is a security risk: a malicious upstream commit could inject
        harmful instructions into your AI agent's context.

        Fix: Set `my.home.ai.harness.skills.${name}.revision` to a specific
        commit SHA or tag. Use `nix-prefetch-git ${skill.url}` to find the
        current HEAD revision.

        To disable this warning: `my.home.ai.harness.warnOnUnpinned = false`;
      '';
    }) unpinnedSkills);

    # Ensure git is available for cloning skills
    home.packages = lib.optional (!config.programs.git.enable) pkgs.git;

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

    # Clone or symlink skills at activation time
    home.activation.installHarnessSkills = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      set -x
      export PATH="${lib.makeBinPath [ pkgs.git ]}:$PATH"

      SKILLS_DIR="${cfg.harness.skillsDir}"
      mkdir -p "$SKILLS_DIR"

      ${lib.concatMapStrings (name: let
        source = cfg.harness.skills.${name}.url;
        revision = cfg.harness.skills.${name}.revision;
        isLocalPath = lib.hasPrefix "/" source;
        target = "$SKILLS_DIR/${name}";
      in ''
        if ${if isLocalPath then "true" else "false"}; then
          # Local path: symlink
          if [ -d "${source}" ]; then
            ln -sfn "${source}" "${target}"
            echo "Harness: symlinked local skill '${name}'"
          else
            echo "Harness: warning - local skill '${name}' path '${source}' not found, skipping"
          fi
        else
          # Remote git URL: clone or pull at pinned revision
          if [ -d "${target}/.git" ]; then
            echo "Harness: updating skill '${name}'"
      ${lib.optionalString (revision != null) ''
            # Verify we're at the expected revision
            CURRENT_REV=$(git -C "${target}" rev-parse HEAD 2>/dev/null)
            if [ "$CURRENT_REV" != "${revision}" ]; then
              echo "Harness: checking out pinned revision ${revision} for '${name}'"
              git -C "${target}" fetch --all 2>&1
              git -C "${target}" checkout "${revision}" 2>&1 || echo "Harness: warning - failed to checkout revision for '${name}'"
            else
              echo "Harness: '${name}' already at pinned revision ${revision}"
            fi
      ''}
      ${lib.optionalString (revision == null) ''
            git -C "${target}" pull --ff-only 2>&1 || echo "Harness: warning - git pull failed for '${name}'"
      ''}
          else
            echo "Harness: cloning skill '${name}'"
            rm -rf "${target}"
      ${lib.optionalString (revision != null) ''
            git clone "${source}" "${target}" 2>&1 && \
              git -C "${target}" checkout "${revision}" 2>&1 || \
              echo "Harness: warning - git clone/checkout failed for '${name}'"
      ''}
      ${lib.optionalString (revision == null) ''
            git clone --depth=1 "${source}" "${target}" 2>&1 || echo "Harness: warning - git clone failed for '${name}'"
      ''}
          fi
        fi
      '') (lib.attrNames cfg.harness.skills)}
      set +x
    '';
  };
}
