{
  config,
  pkgs,
  searchModelByRole,
  ...
}:
let
  cfg = config.my.home.ai;
  configDirectory = "${config.xdg.configHome}/codex";

  dummyEnvKey = "OPENAI_API_KEY"; # just-every/code allows only OPENAI_API_KEY

  # Create a wrapped version of the "codex" package.
  # This forces $CODEX_HOME to always point to $XDG_CONFIG_DIRECTORY.
  # See: https://github.com/openai/codex/issues/1980
  #
  # And integrate to litellm.
  codex-wrapped = pkgs.symlinkJoin {
    name = "codex";

    paths = [
      pkgs.codex
      # pkgs.code # just-every/code: codex alternative
    ];

    nativeBuildInputs = with pkgs; [
      makeWrapper
    ];

      # makeWrapper $out/bin/code $out/bin/codex \
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
      model_providers = builtins.listToAttrs (
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
      mcp_servers = { codex = { command = "mcp-remote-group"; args = ["codex"]; }; };
    };

  shellAliases = {
    cx = "codex";
  };
in
{
  home.packages = [
    codex-wrapped

    # Frequently use
    pkgs.tree
  ];

  xdg.configFile = {
    "codex/.gitkeep".text = "";
    "codex/AGENTS.md".text = config.my.home.ai.prompts.instructions."AGENTS.md".text;
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
