{
  config,
  lib,
  pkgs,
  searchModelByRole,
  ...
}:
let
  cfg = config.my.home.ai;

  opencode = pkgs.symlinkJoin {
    name = pkgs.opencode.pname;
    paths = [ pkgs.opencode ]
      # For built-in lsp, set some applications' PATH
      ++ (lib.optionals config.my.home.languages.python.enable [
        pkgs.pyright # for built-in python lsp
      ]);
  };

  shellAliases = {
    oc = "opencode";
  };

  # ── Merge built-in + extra abstract sub-agent profiles ───────────────
  allProfiles = cfg.subagents.profiles // cfg.subagents.extraProfiles;

  # Generate OpenCode agent entries from abstract profiles.
  # OpenCode supports both JSON (opencode.json "agent" attr) and per-file
  # markdown in ~/.config/opencode/agents/.
  # We emit per-file markdown for each profile.
  opencodeAgentEntries = lib.mapAttrs (name: profile:
    let
      model = searchModelByRole profile.model_role;
      modelStr = if model != null then "${model.provider}/${model.model}" else null;
    in
    {
      inherit name;
      description = profile.description;
      mode = "subagent";
      model = modelStr;
      temperature = if profile.reasoning_effort == "high" then 0.1 else if profile.reasoning_effort == "low" then 0.7 else 0.3;
      prompt = profile.instructions;
      permission = {
        edit = if profile.sandbox_mode == "read-only" then "deny" else "allow";
        bash = if profile.sandbox_mode == "danger-full-access" then "allow" else "ask";
      };
    }
  ) allProfiles;

  # JSON config inline agent entries (for opencode.json)
  opencodeJsonAgents = lib.mapAttrs (name: entry: {
    description = entry.description;
    mode = "subagent";
    model = entry.model;
    temperature = entry.temperature;
    prompt = entry.prompt;
    permission = entry.permission;
  }) opencodeAgentEntries;

  # Markdown agent files for ~/.config/opencode/agents/
  opencodeAgentFiles = lib.mapAttrs' (name: entry: {
    name = "opencode/agents/${name}.md";
    value.text = ''
      ---
      description: ${entry.description}
      mode: subagent
      ${lib.optionalString (entry.model != null) "model: ${entry.model}"}
      temperature: ${builtins.toString entry.temperature}
      permission:
        edit: ${if entry.permission.edit == "allow" then "allow" else "deny"}
        bash: ${if entry.permission.bash == "allow" then "allow" else "ask"}
      ---

      ${entry.prompt}
    '';
  }) opencodeAgentEntries;

  # Only generate when "opencode" is listed as a subagent target
  generateOpencodeAgents = builtins.elem "opencode" cfg.subagents.targets;

  createProviders = providers:
    builtins.listToAttrs (map (p: {
      name = p.name;
      value = {
        npm = "@ai-sdk/openai-compatible";
        name = "${lib.strings.toUpper (lib.strings.substring 0 1 p.name)}${lib.strings.substring 1 (builtins.stringLength p.name - 1) p.name} (local)";
        options.baseURL = "${p.url}/v1";
        models = builtins.listToAttrs (map (m: {
          name = m.model;
          value = { name = m.model; };
        }) p.models);
      };
    }) providers);
in
{
  home.packages = with pkgs; [
    opencode
  ];

  xdg.configFile = lib.mkMerge [
    {
      "opencode/opencode.json".text = builtins.toJSON (
        {
          "$schema" = "https://opencode.ai/config.json";
          theme = "github";
          autoupdate = false;
          share = "disabled";

          model =
            let modelInfo = searchModelByRole "edit";
            in "${modelInfo.provider}/${modelInfo.model}";
          provider = createProviders cfg.providers;

          small_model =
            let modelInfo = searchModelByRole "autocomplete";
            in "${modelInfo.provider}/${modelInfo.model}";

          permission = {
            edit = "allow";
            bash = {
              "*" = "ask";
              "ls" = "allow";
              "tree" = "allow";
              "cat" = "allow";
              "head" = "allow";
              "tail" = "allow";
              "rg" = "allow";
              "fd" = "allow";
              "which" = "allow";
              "ps aux" = "allow";
              "git status" = "allow";
              "git diff" = "allow";
              "git log" = "allow";
              "rm -rf" = "deny";
              "sed" = "deny";
              "awk" = "deny";
            };
            webfetch = "allow";
          };

          lsp =
            let lang = config.my.home.languages;
            in (lib.optionalAttrs lang.nix.enable {
              nix = {
                command = [ (lib.getExe pkgs.nixd) ];
                extensions = [ "nix" ];
              };
            }) // (lib.optionalAttrs lang.java.enable {
              java = {
                command = [ (lib.getExe pkgs.jdt-language-server) ];
                extensions = [ "java" ];
                disabled = config.my.home.languages.java.enable;
              };
            });

          formatter.nix = {
            command = [ (lib.getExe pkgs.nixfmt-rfc-style) ];
            extensions = [ "nix" ];
          };

          agent = lib.optionalAttrs generateOpencodeAgents opencodeJsonAgents;
        }
        // {
          mcp = lib.optionalAttrs config.my.home.mcp.hub.client.enable {
            opencode = {
              type = "local";
              enabled = true;
              command = [ "mcp-remote-group-primary" "opencode" ];
            };
          };
        }
      );

      "opencode/AGENTS.md".source = config.my.home.ai.prompts.instructions."AGENTS.md".source;
    }
    (lib.optionalAttrs generateOpencodeAgents opencodeAgentFiles)
  ];

  programs = {
    bash.shellAliases = shellAliases;
    fish.shellAbbrs = shellAliases;
  };
}
