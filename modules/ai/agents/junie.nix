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
  agentsPath = "junie/agents";

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
          --set JUNIE_HOME  ${config.xdg.dataHome}/junie \
          --set JUNIE_SHARE_ANONYMOUS_STATISTICS false \
          --set JUNIE_CONFIG_LOCATION ${config.xdg.configFile.${configPath}.source}
      '';
  };

  # ── Merge built-in + extra abstract sub-agent profiles ───────────────
  allProfiles = cfg.subagents.profiles // cfg.subagents.extraProfiles;

  # ── Map sandbox_mode → Junie tool groups ─────────────────────────────
  sandboxToTools = sandbox:
    if sandbox == "read-only" then [ "Read" "Glob" "Grep" ]
    else if sandbox == "workspace-write" then [ "Read" "Glob" "Grep" "Write" "Edit" ]
    # danger-full-access: omit tools field → all tools
    else null;

  sandboxToPermissionMode = sandbox:
    if sandbox == "read-only" then "plan"
    else if sandbox == "workspace-write" then "acceptEdits"
    else "bypassPermissions";

  escapeYamlString = value:
    lib.replaceStrings [ "\\" "\"" "\n" ] [ "\\\\" "\\\"" "\\n" ] value;

  # ── Generate Junie CLI subagent .md files ────────────────────────────
  # Format: junie/agents/<name>.md (YAML frontmatter + Markdown body)
  # Docs: https://junie.jetbrains.com/docs/junie-cli-subagents.html
  junieAgentConfigs = lib.mapAttrs' (name: profile:
    let
      resolvedModel = searchModelByRole profile.model_role;
      tools = sandboxToTools profile.sandbox_mode;
      toolsLine = if tools != null then
        "tools: [${lib.concatMapStringsSep ", " (tool: "\"${tool}\"") tools}]"
      else
        "";
      modelLine = lib.optionalString (resolvedModel != null) (
        "model: \"${escapeYamlString resolvedModel.model}\""
      );
    in
    lib.nameValuePair "${agentsPath}/${name}.md" {
      text = ''
        ---
        name: "${escapeYamlString name}"
        description: "${escapeYamlString profile.description}"
        ${toolsLine}
        ${modelLine}
        permissionMode: "${sandboxToPermissionMode profile.sandbox_mode}"
        reasoningLevel: "${profile.reasoning_effort}"
        ---

        ${profile.instructions}
      '';
    }
  ) allProfiles;

  generateJunieAgents = cfg.subagents.enable && builtins.elem "junie" cfg.subagents.targets;
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
            brave = true;
            auto-update = false;
            agent-locations = [ "${config.xdg.configHome}/junie/agents" ];
          }
          // cfg.junie.extraSettings
        );
      }
      (lib.optionalAttrs generateJunieAgents junieAgentConfigs)
    ];
  };
}
