# ZeroStack: lightweight Rust coding agent. https://github.com/gi-dellav/zerostack
{
  config,
  pkgs,
  lib,
  searchModelByRole,
  ...
}:
let
  cfg = config.my.home.ai;
  harness = cfg.harness;

  # Shared builder turning this agent's sessions into a ctx history source.
  # Imported rather than read off `harness.memory`: deriving the plugin and unit
  # from arguments keeps this contribution out of the namespace it lands in,
  # which is what building a shared registry there evaluated as infinite
  # recursion for. Only `memory.package` is read, and nothing here contributes
  # to that.
  historySources = import ../harness/memory/history-source.nix { inherit lib pkgs; };

  # zerostack's own sessions, exported for ctx. The exporter ships here, so the
  # plugin and refresh unit are built in place rather than declared into a
  # registry elsewhere. Its exporter takes no arguments at all, so the
  # destination can only arrive by environment variable.
  zerostackHistory = historySources.mkHistorySource {
    package = config.my.home.ai.harness.memory.package;
    source = {
      providerKey = "zerostack";
      sourceFormat = "zerostack-session-json-v1";
      exporter = {
        script = ../harness/memory/plugins/zerostack/zerostack-ctx-export;
        # Takes no arguments, so the destination can only arrive by environment.
        outputEnvVar = "ZEROSTACK_CTX_HISTORY_PATH";
        environment.ZEROSTACK_SESSION_DIR = "${config.xdg.dataHome}/zerostack/sessions";
      };
    };
  };

  chatModel = searchModelByRole "chat";
  reviewModel = searchModelByRole "review";
  workerModel = searchModelByRole "worker";

  apiKeyEnvOf = provider:
    let
      name = provider.api-key-env;
    in
    if name != null && builtins.match "[A-Z0-9_]+" name != null then name else null;

  # ZeroStack calls `/chat/completions` for custom OpenAI-compatible providers.
  # Shared provider URLs carry only the origin, so append the `/v1` API prefix.
  zerostackProviders = lib.mapAttrs' (
    name: provider:
      let
        apiKeyEnv = apiKeyEnvOf provider;
      in
      lib.nameValuePair name (
        {
          provider_type = "openai";
          base_url = "${lib.removeSuffix "/" provider.url}/v1";
          api_style = "completions";
        }
        // lib.optionalAttrs (apiKeyEnv != null) {
          api_key_env = apiKeyEnv;
        }
      )
  ) (lib.listToAttrs (map (provider: lib.nameValuePair provider.name provider) cfg.providers));

  roleModels = lib.filterAttrs (_: model: model != null) {
    chat = chatModel;
    review = reviewModel;
    worker = workerModel;
  };

  # Quick-model aliases let ZeroStack route the subagent and prompt modes to the
  # role selected by the shared model registry, including across providers.
  quickModels = lib.mapAttrs (_: model: {
    provider = model.provider;
    model = model.model;
  }) roleModels;

  subagentModel =
    if workerModel != null then "worker"
    else null;

  # CONFIG.md documents advisor.model but not an advisor provider field. Only
  # configure it automatically when the chat and review models share a provider.
  advisorModel =
    if chatModel != null && reviewModel != null && chatModel.provider == reviewModel.provider
    then reviewModel
    else null;

  baseMcpServers = lib.mapAttrs (
    _: mcp:
      {
        command = mcp.command;
        args = mcp.args;
        connect_timeout_secs = 10;
        tool_timeout_secs = mcp.timeout;
        connect_retries = 1;
      }
      // lib.optionalAttrs (mcp.env != { }) {
        env = mcp.env;
      }
  ) (lib.filterAttrs (_: mcp: mcp.enabled) harness.mcpServers);

  zerostackMcpServers = baseMcpServers // cfg.zerostack.extraMcpServers;
  configureMcpServers = harness.enable || cfg.zerostack.extraMcpServers != { };

  settings = lib.my.deepMerge
    (
      {
        default_prompt = "code";
        default_permission_mode = "yolo"; # Use `fence` together
        compact_enabled = true;
        show_reasoning = false;
        show_tool_details = false; # Default: 3
        deny_repeated_reads = true;
        # mouse_capture = false; # Use terminal emulator. Default: true.
        "auto-update-prompts" = false;
        "auto-update-themes" = false;
        "enable-exa-mcp" = false;
      }
      // lib.optionalAttrs (chatModel != null) {
        provider = chatModel.provider;
        model = chatModel.model;
      }
      // lib.optionalAttrs (zerostackProviders != { }) {
        custom_providers = zerostackProviders;
      }
      // lib.optionalAttrs (quickModels != { }) {
        quick_models = quickModels;
      }
      // lib.optionalAttrs (subagentModel != null) {
        subagent_model = subagentModel;
      }
      // lib.optionalAttrs (advisorModel != null) {
        advisor = {
          enabled = true;
          model = advisorModel.model;
        };
      }
      // lib.optionalAttrs configureMcpServers {
        mcp_servers = zerostackMcpServers;
      }
      // lib.optionalAttrs (chatModel != null) {
        prompt_to_model = {
          code = "chat";
        }
        // lib.optionalAttrs (reviewModel != null) {
          review = "review";
        };
      } // lib.optionalAttrs harness.enable {
        rtk = {
          enabled = true;
          path = lib.getExe harness.codingAgentTools.rtk.package;
        };
      }
    ) cfg.zerostack.extraSettings;

  # Zerostack calls SessionStart hooks synchronously and therefore waits them on startup.
  sessionStartHooks = lib.optionals harness.enable [
  #   {
  #     type = "command";
  #     command = "${harness.hooks.refreshIndex.package}/bin/refresh-index .codegraph ${harness.codingAgentTools.codegraph.package}/bin/codegraph sync --quiet";
  #     timeout = 60;
  #   }
  #   {
  #     type = "command";
  #     command = "${harness.hooks.refreshIndex.package}/bin/refresh-index .zvec-grep ${harness.codingAgentTools.zg.package}/bin/zg index";
  #     timeout = 60;
  #   }
  ];

  preToolHooks =
    (lib.optionals harness.enable [
      # rtk hooks is integrated by native. See config.
    ])
    ++ (lib.optionals (harness.sandbox.enable) [
      {
        type = "command";
        command = lib.getExe harness.hooks.fenceAudit.package;
        timeout = 10;
      }
    ]);

  generatedHookSettings = {
    hooks =
      (lib.optionalAttrs (sessionStartHooks != [ ]) {
        SessionStart = [ { hooks = sessionStartHooks; } ];
      })
      // (lib.optionalAttrs (preToolHooks != [ ]) {
        PreToolUse = [
          {
            matcher = "Bash";
            hooks = preToolHooks;
          }
        ];
      });
  };

  hooksEnabled = harness.enable || harness.sandbox.enable;
  hookSettings = generatedHookSettings;

  zerostackPkg = pkgs.zerostack.overrideAttrs (_: {
    # The upstream Nix overlay builds the Cargo package with default features.
    # Add opt-in features required by this module (and any user-requested extras).
    #
    # Ignore old.cargoBuildFeatures that includes "acp" "memory" etc: https://github.com/gi-dellav/zerostack/blob/3eda478ac8ef8205bc016e8e4d9f0b930c93f885/nix/package/zerostack.nix#L32
    cargoBuildFeatures = lib.unique (
      ["mcp" "subagents" "status-signals" "logging"]
      ++ [ "multithread" "hooks" "advisor" "rtk" ]
    );
  });

  zerostack = pkgs.writeShellApplication {
    name = "zerostack";
    runtimeInputs = [ zerostackPkg ];
    runtimeEnv = {
      ZS_CONFIG_DIR = "${config.xdg.configHome}/zerostack";
    } // cfg.zerostack.environmentVariables;
    text = ''
      # Preserve a supplied key; use a placeholder for providers that do not need auth.
      OPENAI_API_KEY="''${OPENAI_API_KEY:-dummy}"
      export OPENAI_API_KEY
      exec ${lib.getExe zerostackPkg} "$@"
    '';
  };

  shellAliases = {
    zs = "zerostack";
  };
in
{
  options.my.home.ai.zerostack = {
    enable = lib.mkEnableOption "Enable ZeroStack coding agent";

    environmentVariables = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Additional environment variables set for ZeroStack.";
    };

    extraSettings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Additional ZeroStack config.toml settings, merged after generated settings.";
    };

    extraMcpServers = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Additional entries for ZeroStack's [mcp_servers] table.";
    };
  };

  config = lib.mkIf cfg.zerostack.enable {
    home.packages = [ zerostack ];

    programs.bash.shellAliases = shellAliases;
    programs.fish.shellAbbrs = shellAliases;

    xdg.configFile = lib.mkMerge [
      {
        # ZeroStack may create/update its config at runtime, so keep the Nix
        # source separately and install a writable config.toml at activation.
        "zerostack/config.toml.orig".source = lib.my.toToml settings;
      }
      (lib.optionalAttrs hooksEnabled {
        "zerostack/settings.json".source = pkgs.writeText "zerostack-settings.json" (builtins.toJSON hookSettings);
      })
    ];
    home.activation.installZerostackConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      rm -f "${config.xdg.configHome}/zerostack/config.toml"
      install -m 644 -D "${config.xdg.configHome}/zerostack/config.toml.orig" "${config.xdg.configHome}/zerostack/config.toml"
    '';


    # Nothing indexes this history without ctx itself, hence the second gate on
    # `memory.enable`.
    xdg.dataFile = lib.mkIf config.my.home.ai.harness.memory.enable zerostackHistory.xdg.dataFile;
    systemd.user = lib.mkIf config.my.home.ai.harness.memory.enable zerostackHistory.systemd.user;
  };
}
