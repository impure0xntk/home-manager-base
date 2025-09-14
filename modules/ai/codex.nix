{
  config,
  lib,
  pkgs,
  prompts,
  searchModelByRole,
  ...
}:
let
  cfg = config.my.home.ai;
  configDirectory = "${config.xdg.configHome}/codex";

  dummyEnvKey = "DUMMY_API_KEY";

  # Create a wrapped version of the "codex" package.
  # This forces $CODEX_HOME to always point to $XDG_CONFIG_DIRECTORY.
  # See: https://github.com/openai/codex/issues/1980
  #
  # And integrate to litellm.
  codex-wrapped = pkgs.symlinkJoin {
    name = "codex";

    paths = [
      pkgs.codex
    ];

    buildInputs = [
      pkgs.makeWrapper
    ];

    postBuild = ''
      wrapProgram $out/bin/codex \
        --set CODEX_HOME ${configDirectory} \
        --set ${dummyEnvKey} dummy
    '';
  };

  settings =
    let
      chatModel = searchModelByRole "chat";
    in
    {
      # model/provider
      model = chatModel.model;
      model_provider = chatModel.provider;
      providers = builtins.listToAttrs (
        builtins.map (provider: {
          name = provider.name;
          value = {
            name = provider.name;
            base_url = "${provider.url}";
            env_key = dummyEnvKey;
          };
        }) cfg.providers
      );
      model_reasoning_effort = "high";
      hide_agent_reasoning = true;

      # policy: strict
      approval_policy = "untrusted";
      sandbox_mode = "read-only";

      preferred_auth_method = "apikey";

      profiles = {
        full_auto = {
          approval_policy = "on-request";
          sandbox_mode = "workspace-write";
        };
        readonly_quiet = {
          approval_policy = "never";
          sandbox_mode = "read-only";
        };
      };

      tools = {
        web_search = true;
      };
      mcp_servers = lib.optionalAttrs (builtins.hasAttr "codex" config.my.home.mcp.serverJsonContents) config.my.home.mcp.serverJsonContents.codex.mcpServers;
    };

  shellAliases = {
    cx = "codex";
  };
in
{
  home.packages = [
    codex-wrapped
  ];

  xdg.configFile = {
    "codex/.gitkeep".text = "";
    "codex/AGENTS.md".text =
      with prompts._snippet;
      with prompts.function; ''
      ${charm}
      ${japanese.input}
      ${japanese.output}
    '';
    # "codex/prompts/commit.md".text = prompts.commit.conventional;
  };

  home.activation."codex-fix-config" =
    let
      toml = "${configDirectory}/config.toml";
    in
    ''
      if ! test -e ${toml}; then
        touch ${toml}
      fi
      cp ${toml}{,.bak}
      ${pkgs.dasel}/bin/dasel -r toml -w json -f ${toml} \
        | ${pkgs.jq}/bin/jq '. * ${builtins.toJSON settings}' \
        | ${pkgs.dasel}/bin/dasel -r json -w toml > ${toml}.new
      mv ${toml}{.new,}
    '';

  programs = {
    bash.shellAliases = shellAliases;
    fish.shellAbbrs = shellAliases;
  };
}
