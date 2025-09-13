{
  config,
  lib,
  pkgs,
  searchModelByRole,
  prompts,
  ...
}:
let
  cfg = config.my.home.ai;
  configDirectory = "${config.xdg.configHome}/claude/";

  claude-code-wrapped = pkgs.writeShellApplication {
    name = "claude";
    runtimeInputs = with pkgs; [
      claude-code
      claude-code-router
      ripgrep
    ];
    text = ''
      CLAUDE_CONFIG_DIR=${configDirectory} ccr code "$@"
    '';
  };

  # Convert existing provider configuration to claude-code-router format
  claudeCodeRouterProviders = builtins.map (
    provider:
    let
      # Determine API base URL based on provider type
      apiBaseUrl = "${provider.url}/v1/chat/completions";
    in
    {
      name = provider.name;
      api_base_url = apiBaseUrl;
      api_key = "\${${lib.strings.toUpper provider.name}_API_KEY}"; # dummy
      models = builtins.map (m: m.model) provider.models;
    }
  ) cfg.providers;

  # Generate claude-code-router config.json content
  claudeCodeRouterConfig = {
    # LOG = true;
    # LOG_LEVEL = "debug";
    API_TIMEOUT_MS = 10000;
    Providers = claudeCodeRouterProviders;
    Router = {
      default =
        let
          chatModel = searchModelByRole "edit";
        in
        if chatModel != null then "${chatModel.provider},${chatModel.model}" else "";
      background =
        let
          ollamaModels = builtins.filter (p: p.name == "ollama") cfg.providers;
          ollamaModel =
            if ollamaModels != [ ] then builtins.head (builtins.head ollamaModels).models else null;
        in
        if ollamaModel != null then "ollama,${ollamaModel.model}" else "";
      think =
        let
          editModel = searchModelByRole "chat";
        in
        if editModel != null then "${editModel.provider},${editModel.model}" else "";
    };
  };

  shellAliases = {
    cc = "claude";
  };
in
{
  home.packages = [
    claude-code-wrapped
  ];
  systemd.user.services.claude-code-router = {
    Unit = {
      Description = "claude-code-router daemon";
      Requires = [ "litellm.service" ];
      After = [ "litellm.service" ];
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.claude-code-router}/bin/ccr start";
      Restart = "always";
      WorkingDirectory = "%h";
    };
  };

  home.file.".claude-code-router/config.json".text = builtins.toJSON (
    claudeCodeRouterConfig
    // {
      StatusLine = {
        enabled = true;
        currentStyle = "default";
        default = {
          modules = [
            {
              type = "workDir";
              icon = "📁";
              text = "{{workDirName}}";
              color = "bright_blue";
            }
            {
              type = "gitBranch";
              icon = config.programs.starship.settings.git_branch.symbol;
              text = "{{gitBranch}}";
              color = "bright_green";
            }
            {
              type = "model";
              icon = "🤖";
              text = "{{model}}";
              color = "bright_yellow";
            }
            {
              type = "usage";
              icon = "📊";
              text = "{{inputTokens}} → {{outputTokens}}";
              color = "bright_magenta";
            }
          ];
        };
        # fontFamily = "Hack Nerd Font Mono";
      };
    }
  );
  xdg.configFile = let
    files = [
      {
        name = "CLAUDE.md";
        text = with prompts;
          function.withNoThink (
            function.toJapanese chat.shell.default);
      }
      {
        name = "settings.json";
        text = builtins.toJSON {
          autoUpdates = false;
          theme = "dark";
          verbose = true;

          permissions = {
            allow = [
            ];
            deny = [
              "Bash(rm:*)"
              "WebFetch(domain:github.com)"
            ];
            disableBypassPermissionsMode = "disable";
          };
          env = {
            BASH_DEFAULT_TIMEOUT_MS = 300000;
            BASH_MAX_TIMEOUT_MS = 300000;
            CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR = 1;

            CLAUDE_CODE_IDE_SKIP_AUTO_INSTALL = 1;
            USE_BUILTIN_RIPGREP = 0;

            DISABLE_AUTOUPDATER = 1;
            DISABLE_BUG_COMMAND = 1;
            DISABLE_ERROR_REPORTING = 1;
            DISABLE_TELEMETRY = 1;
            CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = 1;

            CLAUDE_CODE_ENABLE_TELEMETRY = 0;
            DISABLE_COST_WARNINGS = 1;
            DISABLE_NON_ESSENTIAL_MODEL_CALLS = 1;
          };
          includeCoAuthoredBy = false;

          statusLine = {
            type = "command";
            command = "${pkgs.claude-code-router}/bin/ccr statusline";
          };
        };
      }
    ];
  in builtins.listToAttrs (
    builtins.map (v: {
      name = "claude/${v.name}";
      value.text = v.text;
    }) files
  );

  home.activation."add-mcpServers" = let
    mcpServers = lib.optionalAttrs (builtins.hasAttr "claude-code" config.my.home.mcp.serverJsonContents) config.my.home.mcp.serverJsonContents.claude-code.mcpServers;
    json = "${configDirectory}/.claude.json";
  in ''
    if ! test -e ${json}; then
      echo "{}" > ${json}
    fi
    cp ${json}{,.bak}
    ${pkgs.jq}/bin/jq '.mcpServers = ${builtins.toJSON mcpServers}' ${json} > ${json}.new
    mv ${json}{.new,}
  '';

  programs.vscode.profiles.default = {
    extensions = pkgs.nix4vscode.forVscode [
      "Anthropic.claude-code"
    ];
  };

  programs = {
    bash.shellAliases = shellAliases;
    fish.shellAbbrs = shellAliases;
  };
}
