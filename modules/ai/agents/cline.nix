# Cline CLI agent: https://docs.cline.bot/cli/cli-reference
#
# Cline reads no XDG variable at all: its state root is `~/.cline` and its
# settings directory is `~/.cline/data/settings` resolved independently, so the
# wrapper redirects both into the Home Manager config home. Everything below
# them is then declarative.
#
# Only documented surfaces are projected here. Sub-agent profiles are
# deliberately not translated: Cline's subagents are prompt-driven
# (`use_subagents`) rather than definition-file driven, so there is no
# per-profile file to generate.
{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.my.home.ai;

  dataDir = "${config.xdg.configHome}/cline";

  exportEnv = name: value: "export ${name}=${lib.escapeShellArg value}";

  # `my.home.ai.agents` already carries per-agent shell allow/deny patterns for
  # the git worktree runner, and Cline speaks the same shape natively through
  # CLINE_COMMAND_PERMISSIONS. Reuse the cline entry rather than declaring a
  # second policy. `ask` has no Cline counterpart: it falls through to the
  # interactive prompt, which is what the agent expects anyway.
  clineAgent = lib.findFirst (agent: agent.name == "cline") null cfg.agents;
  ruleCommands =
    action:
    map (rule: rule.command) (
      lib.filter (rule: rule.action == action) (clineAgent.autoApprovalRules or [ ])
    );

  # Cline auto-approves every tool by default outside ACP mode
  # (`--auto-approve` defaults to true), so an `allow` list is what actually
  # constrains the shell. Redirects stay closed because `> file` turns an
  # approved read into an unapproved write.
  commandPermissions = {
    allow = ruleCommands "allow";
    deny = ruleCommands "deny";
    allowRedirects = false;
  };

  # stdio MCP servers shared through the harness tool registry.
  # Cline reads them from the settings directory, i.e.
  # `$CLINE_DATA_DIR/settings/cline_mcp_settings.json`, not from a `mcp.json`
  # next to the rules and skills. https://docs.cline.bot/mcp/mcp-overview
  mcpServers = lib.mapAttrs' (name: server: lib.nameValuePair name server) (
    lib.mapAttrs (
      _name: mcp:
      {
        command = mcp.command;
        args = mcp.args;
        disabled = !mcp.enabled;
      }
      // lib.optionalAttrs (mcp.env != { }) { env = mcp.env; }
    ) cfg.harness.mcpServers
    // cfg.cline.extraMcpServers
  );

  # `settings.provider` is the Cline provider id, not a display name: `cline
  # auth -b <url>` rejects anything outside its catalog with "base URL is only
  # supported for OpenAI and OpenAI-compatible providers".
  #
  # The API key is deliberately absent. Cline stores it in this file in plain
  # text, which would put the secret in the Nix store; it is resolved from the
  # environment variable the provider declares instead, so it belongs in
  # `environmentVariables` fed from sops.
  providerSettings = {
    version = 1;
    # `or` does not apply here: `defaultProvider` resolves to null rather than
    # to a missing attribute.
    lastUsedProvider =
      if cfg.cline.defaultProvider == null then
        (lib.head cfg.cline.providers).id
      else
        cfg.cline.defaultProvider;
    modes = { };
    providers = builtins.listToAttrs (
      map (provider: {
        name = provider.id;
        value = {
          settings = {
            provider = provider.kind;
            inherit (provider) model;
          }
          // lib.optionalAttrs (provider.baseUrl != null) {
            inherit (provider) baseUrl;
          };
          # Required by the schema but never read back: Cline only stamps it
          # when it writes. A constant keeps the derivation reproducible.
          updatedAt = "1970-01-01T00:00:00.000Z";
          tokenSource = "manual";
        };
      }) cfg.cline.providers
    );
  };

  environment = cfg.cline.environmentVariables // {
    # `--data-dir` alone relocates rules, skills, hooks, and sessions, but the
    # settings directory is still resolved from `$HOME/.cline/data`, so the
    # data root has to be redirected separately or every managed settings file
    # is silently ignored.
    CLINE_DATA_DIR = "${dataDir}/data";
    CLINE_COMMAND_PERMISSIONS = builtins.toJSON commandPermissions;
  };

  cline-wrapped = pkgs.writeShellApplication {
    name = pkgs.cline.meta.mainProgram;
    runtimeInputs = [ pkgs.cline ];
    text = ''
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList exportEnv environment)}
      exec ${lib.getExe pkgs.cline} --data-dir ${lib.escapeShellArg dataDir} "$@"
    '';
  };
in

{
  options.my.home.ai.cline = {
    enable = lib.mkEnableOption "Enable Cline CLI agent.";
    environmentVariables = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = ''
        Additional environment variables set for the cline CLI. A provider API
        key belongs here rather than in a `providers` entry, sourced from sops:
        Cline resolves it from the variable its provider declares, and never
        needs it written to disk.
        CLINE_COMMAND_PERMISSIONS is derived from the `cline` entry of
        `my.home.ai.agents` and always wins over a value set here.
      '';
    };
    extraMcpServers = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
      default = { };
      description = ''
        MCP servers merged into `mcpServers` of the managed
        `cline_mcp_settings.json`, on top of the harness tool registry. Cline
        entry shape: `command` plus `args` for a stdio server, or `type` plus
        `url` and `headers` for a remote one, and optionally `env`, `disabled`,
        and `autoApprove`.
      '';
    };
    providers = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            id = lib.mkOption {
              type = lib.types.str;
              example = "litellm";
              description = ''
                Key of the entry, and the value `cline --provider` expects. Free
                form: it names the entry, not the upstream provider.
              '';
            };
            kind = lib.mkOption {
              type = lib.types.str;
              example = "openai-compatible";
              description = ''
                Cline provider id written to `settings.provider`. Must be one of
                the ids in its provider catalog, otherwise Cline falls back to
                the API defaults and ignores `baseUrl`. `openai-compatible`
                for any OpenAI-shaped endpoint, `ollama` for a local runtime.
              '';
            };
            model = lib.mkOption {
              type = lib.types.str;
              example = "openrouter/stealth/space-bunny-alpha";
              description = "Model id passed to the provider, not prefixed by Cline.";
            };
            baseUrl = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              example = "https://vpn-ai-proxy.example.com/v1";
              description = ''
                Endpoint override. Null leaves the provider's own default, which
                is what a local runtime such as `ollama` wants.
              '';
            };
          };
        }
      );
      default = [ ];
      description = ''
        Model providers written to `settings/providers.json`. Empty leaves the
        file to `cline auth`, so the CLI stays usable without configuration.
        Credentials are not part of an entry; see `environmentVariables`.
      '';
    };
    defaultProvider = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "litellm";
      description = ''
        Id Cline selects at start-up, written to `lastUsedProvider`. Null takes
        the first entry of `providers`.
      '';
    };
    extraSettings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = ''
        Keys written verbatim to the managed `global-settings.json`, next to
        `cline_mcp_settings.json` in the Cline settings directory. Both are only
        managed when this is non-empty, so the interactive `cline config` UI
        keeps owning them otherwise. Because Home Manager owns them once
        written, every key that should survive has to live here.
      '';
    };
  };

  config = lib.mkIf cfg.cline.enable {
    home.packages = [ cline-wrapped ];

    xdg.configFile = lib.mkMerge [
      {
        "cline/data/settings/cline_mcp_settings.json".text = builtins.toJSON { inherit mcpServers; };
        # Cline loads every file under `<dataDir>/rules` into each session, so
        # the shared AGENTS.md is a rule file here rather than a prompt: no
        # `use_skill` round trip and no per-session context cost when unused.
        "cline/rules/AGENTS.md".source = config.my.home.ai.harness.agentsMd.source;
      }
      (lib.optionalAttrs config.my.home.ai.harness.enable {
        "cline/skills" = {
          source = config.lib.file.mkOutOfStoreSymlink config.my.home.ai.harness.skillsDir;
          force = true;
        };
      })
      (lib.optionalAttrs (cfg.cline.extraSettings != { }) {
        "cline/data/settings/global-settings.json".text = builtins.toJSON cfg.cline.extraSettings;
      })
      (lib.optionalAttrs (cfg.cline.providers != [ ]) {
        "cline/data/settings/providers.json".text = builtins.toJSON providerSettings;
      })
    ];
  };
}
