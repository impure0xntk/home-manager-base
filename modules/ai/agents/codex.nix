{
  config,
  pkgs,
  lib,
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

    paths = if cfg.codex.enableJustEveryCode then [
      pkgs.code # just-every/code: codex alternative
    ] else [
      pkgs.codex
    ];

    nativeBuildInputs = with pkgs; [
      makeWrapper
    ];

      # makeWrapper $out/bin/code $out/bin/codex \
      # wrapProgram $out/bin/codex \
    postBuild = (if cfg.codex.enableJustEveryCode then ''
      makeWrapper $out/bin/code $out/bin/codex \
    '' else ''
      wrapProgram $out/bin/codex \
    '') + ''
        --set CODEX_HOME ${configDirectory} --set ${dummyEnvKey} dummy
    '';
  };

  settings =
    {
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
      mcp_servers = { codex = { command = "mcp-remote-group-primary"; args = ["codex"]; }; };
    } // (let
      chatModel = searchModelByRole "chat";
    in lib.optionalAttrs cfg.codex.enableCustomProvider {
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
    }) // (lib.optionalAttrs cfg.codex.enableJustEveryCode {
      tui = {
        theme.name = "dark-zen-garden";
        spinner.name = "brailleDotsClassic";
      };
    });

  shellAliases = {
    cx = "codex";
  };
in
{
  options.my.home.ai.codex = {
    enable = lib.mkEnableOption "Enable Codex agent";
    enableJustEveryCode = lib.mkEnableOption "Enable just-every/code as codex provider";
    enableCustomProvider = lib.mkEnableOption "Enable custom provider configuration";
  };
  config = lib.mkIf cfg.codex.enable {
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
  };
}
