{ lib, ... }:
let
  profileType = lib.types.submodule {
    options = {
      description = lib.mkOption {
        type = lib.types.str;
        description = "Short description displayed in the agent list.";
      };
      instructions = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = "Persistent instructions passed to the subagent.";
      };
      model_role = lib.mkOption {
        type = lib.types.enum [ "chat" "edit" "apply" "autocomplete" ];
        default = "chat";
        description = "Logical model role resolved from the configured providers.";
      };
      reasoning_effort = lib.mkOption {
        type = lib.types.enum [ "low" "medium" "high" ];
        default = "medium";
        description = "Reasoning effort requested from the target agent.";
      };
      sandbox_mode = lib.mkOption {
        type = lib.types.enum [ "read-only" "workspace-write" "danger-full-access" ];
        default = "read-only";
        description = "Abstract execution permission level for the subagent.";
      };
    };
  };

  agentFormats = [
    "codex"
    "goose"
    "opencode"
    "claude"
    "copilot"
    "junie"
  ];
in
{
  options.my.home.ai.subagents = {
    enable = lib.mkEnableOption "abstract sub-agent profile definitions";

    profiles = lib.mkOption {
      type = lib.types.attrsOf profileType;
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
      description = "Named common sub-agent profiles translated by each enabled adapter.";
    };

    extraProfiles = lib.mkOption {
      type = lib.types.attrsOf profileType;
      default = { };
      description = "Additional common sub-agent profiles merged with profiles.";
    };

    targets = lib.mkOption {
      type = lib.types.listOf (lib.types.enum agentFormats);
      default = [ "codex" "junie" "goose" "copilot" ];
      description = "Agent adapters that receive the common sub-agent profiles.";
    };
  };
}
