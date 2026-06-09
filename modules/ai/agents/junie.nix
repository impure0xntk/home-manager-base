{
  config,
  pkgs,
  lib,
  searchModelByRole,
  ...
}:
let
  cfg = config.my.home.ai;

  configPath = "junie/config.json";

  junie-wrapped = pkgs.symlinkJoin {
    name = "junie";
    version = pkgs.junie.version;
    paths = [ pkgs.junie ];
    nativeBuildInputs = with pkgs; [ makeWrapper ];
    postBuild =
      let
        cfgProxy = config.my.home.networks.proxy;
        proxyOpts = if cfgProxy.enable then ''--set JAVA_TOOL_OPTIONS "${cfgProxy.snippet.javaOpts}"'' else "";
      in
      ''
        wrapProgram $out/bin/junie ${proxyOpts} \
          --set JUNIE_CONFIG_LOCATION ${config.xdg.configFile.${configPath}.source}
      '';
  };

  # ── Merge built-in + extra abstract sub-agent profiles ───────────────
  allProfiles = cfg.subagents.profiles // cfg.subagents.extraProfiles;

  # ── Map sandbox_mode → Junie tool groups ─────────────────────────────
  # Junie supports: "read", "edit", "bash", "web", "mcp" tool groups
  sandboxToTools = sandbox:
    if sandbox == "read-only" then [ "read" "search" ]
    else if sandbox == "workspace-write" then [ "read" "search" "edit" ]
    # danger-full-access: omit tools field → all tools
    else null;

  # ── Generate Junie CLI subagent .md files ────────────────────────────
  # Format: ~/.junie/agents/<name>.md (YAML frontmatter + Markdown body)
  # Docs: https://junie.jetbrains.com/docs/junie-cli-subagents.html
  junieAgentConfigs = lib.mapAttrs' (name: profile:
    let
      tools = sandboxToTools profile.sandbox_mode;
      toolsLine = if tools != null
        then "tools: [${lib.concatMapStringsSep ", " (t: "\"${t}\"") tools}]"
        else "";
      # Map reasoning_effort → Junie reasoningLevel
      reasoningLevel = profile.reasoning_effort; # low/medium/high maps directly
    in
    lib.nameValuePair "junie/agents/${name}.md" {
      text = ''
        ---
        name: "${name}"
        description: "${profile.description}"
        ${toolsLine}
        reasoningLevel: "${reasoningLevel}"
        ---

        ${profile.instructions}
      '';
    }
  ) allProfiles;

  generateJunieAgents = builtins.elem "junie" cfg.subagents.targets;
in
{
  options.my.home.ai.junie = {
    enable = lib.mkEnableOption "Enable Junie agent";
    extraSettings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Junie agent settings";
    };
  };

  config = lib.mkIf cfg.junie.enable {
    home.packages = [ junie-wrapped ];

    xdg.configFile = lib.mkMerge [
      {
        ${configPath}.text = builtins.toJSON (
          {
            brave = false;
            auto-update = false;
          }
          // cfg.junie.extraSettings
        );
      }
      (lib.optionalAttrs generateJunieAgents junieAgentConfigs)
    ];
  };
}
