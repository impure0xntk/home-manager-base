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

  opencode = pkgs.symlinkJoin {
    name = pkgs.opencode.pname;
    paths = [
      pkgs.opencode
    ]
    # For built-in lsp, set some applications' PATH
    ++ (lib.optionals config.my.home.languages.python.enable [
      pkgs.pyright # for built-in python lsp
    ]);
  };

  shellAliases = {
    oc = "opencode";
  };
in
{
  home.packages = with pkgs; [
    opencode

    # MCP converter tool
    (writeShellApplication {
      name = "opencode-mcp-converter";
      runtimeInputs = [ jq ];
      text = builtins.readFile ./scripts/opencode-mcp-converter.sh;
    })
  ];

  xdg.configFile =
  let
    createProviders = providers:
      builtins.listToAttrs (map (p: {
        name = p.name;
        value = {
          npm = "@ai-sdk/openai-compatible";
          name = "${lib.strings.toUpper (lib.strings.substring 0 1 p.name)}${lib.strings.substring 1 (builtins.stringLength p.name - 1) p.name} (local)";
          options.baseURL = "${p.url}/v1";
          models = builtins.listToAttrs (map (m: {
            name = m.model;
            value = {
              name = m.model;
            };
          }) p.models);
        };
      }) providers);
  in {
    "opencode/opencode.json".text = builtins.toJSON (
      {
        "$schema" = "https://opencode.ai/config.json";
        theme = "github";
        autoupdate = false;
        share = "disabled";

        model = let modelInfo = searchModelByRole "edit"; in "${modelInfo.provider}/${modelInfo.model}";
        provider = createProviders cfg.providers;

        small_model = let modelInfo = searchModelByRole "autocomplete"; in "${modelInfo.provider}/${modelInfo.model}";

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

        lsp = let
          lang = config.my.home.languages;
        in (lib.optionalAttrs lang.nix.enable {
          nix = {
            command = [(lib.getExe pkgs.nixd)];
            extensions = ["nix"];
          };
        }) // (lib.optionalAttrs lang.java.enable {
          java = {
            command = [(lib.getExe pkgs.jdt-language-server)];
            extensions = ["java"];
            disabled = config.my.home.languages.java.enable;
          };
        });

        formatter = {
          nix = {
            command = [(lib.getExe pkgs.nixfmt-rfc-style)];
            extensions = ["nix"];
          };
        };
      } // lib.optionalAttrs config.my.home.mcp.enable {
          mcp = lib.optionalAttrs (
            builtins.hasAttr "opencode" config.my.home.mcp.servers
              && config.my.home.mcp.hub.enable)
            {
              opencode = {
                type = "local"; enabled = true;
                command = [ "mcp-remote-group" "opencode"];
              };
            };
      }
    );
    "opencode/AGENTS.md".text =
      with prompts._snippet;
      with prompts.function;
      with prompts; ''
      # AGENTS.md

      ## General

      ${charm}

      ## Language

      ${japanese.input}
      ${japanese.output}

      ## CLI tools

      ${tools.alternatives}
      ${tools.constraints}

      ## Security

      ${security}

      ## Communication

      ${agent.autonomous}

      ## Specific MCP Servers Usage

      ${mcp.usage}
    '';
  };

  programs = {
    bash.shellAliases = shellAliases;
    fish.shellAbbrs = shellAliases;
  };
}
