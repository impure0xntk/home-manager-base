{
  config,
  pkgs,
  lib,
  searchModelByRole,
  ...
}:

let
  cfg = config.my.home.ai;

  goose-cli-wrapped = let
    exportEnvVarStrs = lib.mapAttrsToList (name: value: "export ${name}=${value}") config.my.home.ai.goose.environmentVariables;
    exportEnv = lib.concatStringsSep "\n" exportEnvVarStrs;
  in pkgs.writeShellApplication {
    name = pkgs.goose-cli.meta.mainProgram;
    runtimeInputs = [ pkgs.goose-cli ];
    text = ''
      ${exportEnv}
      exec ${lib.getExe pkgs.goose-cli} "$@"
    '';
  };

  gooseConfig = {
    GOOSE_PROVIDER =
      let
        modelInfo = searchModelByRole "edit";
      in
      "${modelInfo.provider}";
    GOOSE_MODEL =
      let
        modelInfo = searchModelByRole "edit";
      in
      "${modelInfo.model}";
    GOOSE_LEAD_MODEL =
      let
        modelInfo = searchModelByRole "chat";
      in
      "${modelInfo.model}";
    GOOSE_LEAD_PROVIDER =
      let
        modelInfo = searchModelByRole "chat";
      in
      "${modelInfo.provider}";
    GOOSE_TEMPERATURE = 0.7;
    GOOSE_MODE = "auto";
    GOOSE_MAX_TURNS = 1000;
    GOOSE_TOOLSHIM = false;
    GOOSE_CLI_MIN_PRIORITY = 0.0;
    GOOSE_CLI_THEME = "dark";
    GOOSE_CLI_SHOW_COST = false;
    GOOSE_AUTO_COMPACT_THRESHOLD = 0.8;
    SECURITY_PROMPT_ENABLED = true;
    SECURITY_PROMPT_THRESHOLD = 0.7;

    extensions = {
      developer = {
        bundled = true;
        enabled = true;
        name = "developer";
        timeout = 300;
        type = "builtin";
      };
      memory = {
        bundled = true;
        enabled = true;
        name = "memory";
        timeout = 300;
        type = "builtin";
      };
      custom = {
        enabled = true;
        name = "custom";
        timeout = 300;
        type = "stdio";
        cmd = "mcp-remote-group-primary";
        args = ["goose"];
      };
    };
  };
in
{
  options.my.home.ai.goose = {
    enable = lib.mkEnableOption "Enable Goose CLI configuration.";
    environmentVariables = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      description = "Additional environment variables to set for goose-cli.";
    };
  };
  config = lib.mkIf cfg.goose.enable {
    home.packages = with pkgs; [
      goose-cli-wrapped
    ];
    xdg.configFile = {
      "goose/config.yaml".source = lib.my.toYaml gooseConfig;
      "goose/AGENTS.md".text = config.my.home.ai.prompts.instructions."AGENTS.md".text;
    } // lib.optionalAttrs (cfg.providers != null) (
      builtins.listToAttrs (
        map (p: {
          name = "goose/custom_providers/custom_${p.name}.json";
          value = {
            source = lib.my.toYaml {
              name = p.name;
              engine = "openai";
              display_name = p.name;
              description = "Custom ${p.name} provider";
              api_key_env = "${lib.strings.toUpper p.name}_API_KEY";
              base_url = "${p.url}/v1/chat/completions";
              models = map (m: {
                name = m.model;
                # context_limit = m.context_limit or 4096;
              }) p.models;
              headers = p.headers or { };
              supports_streaming = p.supports_streaming or true;
            };
          };
        }) cfg.providers
      )
    );
    programs.fish.interactiveShellInit = ''
      ${lib.getExe goose-cli-wrapped} term init fish \
        | ${lib.getExe pkgs.gnused} -e 's@${lib.getExe pkgs.goose-cli}@${lib.getExe goose-cli-wrapped}@g' \
        | source
    '';
    programs.vscode.profiles.default = {
      extensions = pkgs.nix4vscode.forVscode [
        "block.vscode-goose"
      ];
      userSettings = {
        "goose.binaryPath" = lib.getExe goose-cli-wrapped;
      };
    };
  };
}
