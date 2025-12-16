{
  config,
  pkgs,
  lib,
  searchModelByRole,
  ...
}:

let
  cfg = config.my.home.ai;

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
  home.packages = with pkgs; [
    goose-cli
  ];
  xdg.configFile = {
    "goose/config.yaml".source = lib.my.toYaml gooseConfig;
    "goose/AGENTS.md".text = config.my.home.ai.prompts.instructions."AGENTS.md".text;
  } // lib.optionalAttrs (cfg.providers != null) (
    builtins.listToAttrs (
      map (p: {
        name = "goose/custom_providers/${p.name}.yaml";
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
}
