{
  config,
  pkgs,
  lib,
  searchModelByRole,
  ...
}:
let
  cfg = config.my.home.ai;

  # wrapped copilot-cli: force $COPILOT_HOME to $XDG_CONFIG_DIRECTORY
  # See: https://github.com/github/copilot-cli/issues/1750
  copilot-cli-wrapped = pkgs.symlinkJoin {
    name = "copilot-cli";
    version = pkgs.copilot-cli.version;
    paths = [ pkgs.copilot-cli ];
    nativeBuildInputs = with pkgs; [ makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/copilot \
        --set COPILOT_HOME ${config.xdg.configHome}/copilot
    '';
  };

  settings = lib.my.deepMerge {
    autoUpdate = false;
    banner = "never";
    includeCoAuthoredBy = false;
    effortLevel = "high";
  } cfg.copilot-cli.extraSettings;

  # ── Merge built-in + extra abstract sub-agent profiles ───────────────
  allProfiles = cfg.subagents.profiles // cfg.subagents.extraProfiles;

  # ── Map sandbox_mode → Copilot CLI tool allow-list ──────────────────
  sandboxToTools = sandbox:
    if sandbox == "read-only" then [ "read" "search" ]
    else if sandbox == "workspace-write" then [ "read" "search" "edit" ]
    else null; # danger-full-access → all tools (omit field)

  # ── Generate Copilot CLI custom agent .agent.md files ────────────────
  # Format: ~/.copilot/agents/<name>.agent.md (YAML frontmatter + Markdown body)
  # Docs: https://docs.github.com/en/enterprise-cloud@latest/copilot/reference/custom-agents-configuration
  copilotAgentConfigs = lib.mapAttrs' (name: profile:
    let
      tools = sandboxToTools profile.sandbox_mode;
      toolsLine = if tools != null
        then "tools: [${lib.concatMapStringsSep ", " (t: "\"${t}\"") tools}]"
        # danger-full-access: omit tools to allow all
        else "";
    in
    lib.nameValuePair "copilot/agents/${name}.agent.md" {
      text = ''
        ---
        name: "${name}"
        description: "${profile.description}"
        ${toolsLine}
        ---

        ${profile.instructions}

        **Reasoning Effort**: ${profile.reasoning_effort}
      '';
    }
  ) allProfiles;

  generateCopilotAgents = builtins.elem "copilot" cfg.subagents.targets;
in
{
  options.my.home.ai.copilot-cli = {
    enable = lib.mkEnableOption "Enable Copilot CLI agent";
    extraSettings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Copilot CLI agent settings";
    };
  };

  config = lib.mkIf cfg.copilot-cli.enable {
    # TODO: refactor after home-manager 26.05
    home.packages = [ copilot-cli-wrapped ];

    xdg.configFile = lib.mkMerge [
      { "copilot/settings.json".text = builtins.toJSON settings; }
      (lib.optionalAttrs generateCopilotAgents copilotAgentConfigs)
    ];
  };
}
