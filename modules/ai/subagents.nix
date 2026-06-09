{
  config,
  lib,
  ...
}:
let
  cfg = config.my.home.ai;

  # Supported agent format identifiers.
  agentFormats = [
    "codex"     # Codex: ~/.codex/agents/<name>.toml  (TOML)
    "goose"     # Goose: Recipes YAML in GOOSE_RECIPE_PATH
    "opencode"  # OpenCode: opencode.json or per-file markdown in agents/
    "claude"    # Claude Code: .claude/skills/<name>/SKILL.md + command files
    "copilot"   # Copilot CLI: ~/.copilot/agents/<name>.agent.md (custom agents)
    "junie"     # Junie CLI: ~/.junie/agents/<name>.md (native subagents)
    "custom"    # Custom: user-supplied script that writes agent config files
  ];

  # Codex subagent default config template
  codexDefaults = {
    model_reasoning_effort = "medium";
    hide_agent_reasoning = true;
    approval_policy = "untrusted";
    sandbox_mode = "read-only";
  };

  # OpenCode subagent default config template
  opencodeDefaults = {
    temperature = 0.3;
    permission = {
      edit = "allow";
      bash.__default = "ask";
    };
  };
in
{
  options.my.home.ai.subagents = with lib; with lib.types; {
    enable = mkEnableOption "Enable abstract sub-agent profile definitions";

    # ── Built-in profiles ──────────────────────────────────────────────
    # Consumers map these profiles to their own config format.
    # Example: codex uses planner/worker/reviewer; goose uses them as recipe names.
    profiles = mkOption {
      description = ''
        Named sub-agent profiles. Each profile is an abstract description
        of capability, model role, reasoning effort, and sandbox level.
        Agent-specific adapters translate these into per-agent config files.
      '';
      type = attrsOf (submodule {
        options = {
          description = mkOption {
            type = str;
            description = "Human-readable description of this profile's purpose";
          };
          model_role = mkOption {
            type = enum [ "chat" "edit" "apply" "autocomplete" ];
            default = "chat";
            description = "Which model role to look up from provider config";
          };
          reasoning_effort = mkOption {
            type = enum [ "low" "medium" "high" ];
            default = "medium";
            description = "Reasoning effort level";
          };
          sandbox_mode = mkOption {
            type = enum [ "read-only" "workspace-write" "danger-full-access" ];
            default = "read-only";
            description = "Sandbox permission level for this profile";
          };
          instructions = mkOption {
            type = lines;
            default = "";
            description = "Agent-specific developer instructions (prompt body)";
          };
        };
      });
      default = {
        planner = {
          description = "Plan, decompose tasks, and assign work";
          model_role = "chat";
          reasoning_effort = "medium";
          sandbox_mode = "read-only";
          instructions = ''
            You are the plan agent.
            You analyze the task, create detailed plans, and assign work to workers.
          '';
        };
        worker = {
          description = "Execute plans, write code, and verify results";
          model_role = "edit";
          reasoning_effort = "low";
          sandbox_mode = "workspace-write";
          instructions = ''
            You are the worker agent.
            You execute the plan from the plan agent, write code, and verify results.
          '';
        };
        reviewer = {
          description = "Review code for correctness, security, and test coverage";
          model_role = "chat";
          reasoning_effort = "high";
          sandbox_mode = "read-only";
          instructions = ''
            Review code like an owner.
            Prioritize correctness, security, behavior regressions, and missing test coverage.
            Lead with concrete findings, include reproduction steps when possible, and avoid style-only comments unless they hide a real bug.
          '';
        };
      };
    };

    # ── Target agents to generate configs for ──────────────────────────
    targets = mkOption {
      description = ''
        Which agent adapters to emit sub-agent configs for.
        Each selected format writes its own config files from the abstract profiles.
      '';
      type = listOf (enum agentFormats);
      default = [ "codex" "goose" ];
    };

    # ── Custom sub-agents ──────────────────────────────────────────────
    # Users can define arbitrary sub-agent profiles beyond the built-in ones.
    # These merge on top of profiles.
    extraProfiles = mkOption {
      description = ''
        Additional named sub-agent profiles merged with the built-in profiles.
        Useful for domain-specific delegates (e.g. "security-scanner", "doc-writer").
      '';
      type = attrsOf (submodule {
        options = {
          description = mkOption {
            type = str;
            description = "Human-readable description";
          };
          model_role = mkOption {
            type = enum [ "chat" "edit" "apply" "autocomplete" ];
            default = "chat";
          };
          reasoning_effort = mkOption {
            type = enum [ "low" "medium" "high" ];
            default = "medium";
          };
          sandbox_mode = mkOption {
            type = enum [ "read-only" "workspace-write" "danger-full-access" ];
            default = "read-only";
          };
          instructions = mkOption {
            type = lines;
            default = "";
            description = "Developer instructions for this sub-agent";
          };
        };
      });
      default = { };
    };

    # ── Codex adapter settings ─────────────────────────────────────────
    codex = {
      agentsDir = mkOption {
        type = path;
        default = "${config.xdg.configHome}/codex/agents";
        description = "Directory to write Codex agent TOML files";
      };
    };

    # ── Goose adapter settings ─────────────────────────────────────────
    goose = {
      recipeDir = mkOption {
        type = path;
        default = "${config.xdg.configGoose}/recipes";
        description = "Directory to write Goose recipe YAMLs";
      };
      recipePathEnvVar = mkOption {
        type = str;
        default = "GOOSE_RECIPE_PATH";
        description = "Env var name Goose uses to discover recipe directories";
      };
    };

    # ── OpenCode adapter settings ──────────────────────────────────────
    opencode = {
      agentsDir = mkOption {
        type = path;
        default = "${config.xdg.configHome}/opencode/agents";
        description = "Directory to write OpenCode agent markdown files";
      };
    };

    # ── Claude adapter settings ────────────────────────────────────────
    claude = {
      skillsDir = mkOption {
        type = path;
        default = "${config.home.homeDirectory}/.claude/skills";
        description = "Directory to write Claude skill folders";
      };
    };

    # ── Custom adapter shell hook ──────────────────────────────────────
    # For "custom" target: a shell script that receives profile attrs as env vars.
    customHook = mkOption {
      type = nullOr lines;
      default = null;
      description = ''
        Shell script invoked for each profile when "custom" is in targets.
        Environment variables: PROFILE_NAME, PROFILE_DESCRIPTION, PROFILE_MODEL_ROLE,
        PROFILE_REASONING_EFFORT, PROFILE_SANDBOX_MODE, PROFILE_INSTRUCTIONS.
        Write agent config files to the current working directory or as needed.
      '';
    };
  };
}
