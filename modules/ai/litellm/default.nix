# https://github.com/bowmanjd/nix-config/blob/ec086d5cb5be0fc4bc39b12e9f1d132c60b738d5/home-manager/llm/default.nix#L51

{
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.my.home.ai.litellm;
  cfgAi = config.my.home.ai;

  litellm = pkgs.pure-unstable.litellm;

  settingsDefault = {
    litellm_settings = {
      num_retries = 5;
      cache = true;
      cache_params = {
        type = "local";
        # type = "disk";
        # disk_cache_dir = "/tmp/litellm-cache";
      };
      drop_params = true;
    };
  };
  settingsAll = lib.recursiveUpdate settingsDefault cfg.settings;
in
{
  options.my.home.ai.litellm = {
    port = lib.mkOption {
      type = lib.types.int;
      default = 1173;
      description = "Port for the LiteLLM API server.";
    };
    settings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "LiteLLM settings. This outputs to yaml.";
    };
    environmentFilePath = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to the environment file containing API keys for LiteLLM.";
    };
    useSopsNix = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether using sops. If enabled start litellm after sops-nix.service";
    };
    presetModels = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = (import ./models {inherit lib;});
      description = "Preset models";
    };
  };
  config = lib.mkIf cfgAi.enable {
    systemd.user.services = {
      "litellm-ready" = {
        Unit = {
          Description = "Ready for LiteLLM API server";
        };
        Service = {
          Type = "oneshot";
          ExecStart = "${pkgs.coreutils}/bin/mkdir -p %D/litellm";
        };
        Install = {
          WantedBy = [ "default.target" ];
        };
      };

      "litellm" = {
        Unit = rec {
          Description = "LiteLLM API server";
          StartLimitIntervalSec = "120";
          StartLimitBurst = "5";
          After = [
            "litellm-ready.service"
          ]
          ++ (lib.optionals cfg.useSopsNix [
            "sops-nix.service"
          ]);
          Requires = After;
        };
        Service = {
          WorkingDirectory = "%D/litellm";
          ExecStart = "${litellm}/bin/litellm --port ${builtins.toString cfg.port} --config ${lib.my.toYaml settingsAll}";
          EnvironmentFile = lib.mkIf (cfg.environmentFilePath != null) cfg.environmentFilePath;
          Environment = [
            "PRISMA_SCHEMA_ENGINE_BINARY=${pkgs.prisma-engines}/bin/schema-engine"
            "PRISMA_QUERY_ENGINE_BINARY=${pkgs.prisma-engines}/bin/query-engine"
            "PRISMA_QUERY_ENGINE_LIBRARY=${pkgs.prisma-engines}/lib/libquery_engine.node"

            "ANONYMIZED_TELEMETRYFalse"
            "DO_NOT_TRACK=True"
            "SCARF_NO_ANALYTICS=True"
            "DISABLE_ADMIN_UI=True"
            "NO_DOCS=True"
          ]
          ++ (lib.optionals config.my.home.networks.proxy.enable [
            "HTTPS_PROXY=${config.my.home.networks.proxy.default}"
          ]);
          Restart = "on-failure";
          RestartSec = 5;
          StateDirectory = "litellm";
          RuntimeDirectory = "litellm";
          RuntimeDirectoryMode = "0755";
          StandardOutput = "journal";
          StandardError = "journal";
        };
        Install = {
          WantedBy = [ "default.target" ];
        };
      };
    };
  };
}
