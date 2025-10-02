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
    createMcp = mcpServers:
      lib.mapAttrs (name: config:
        let
          isRemote = config ? "url";
        in
        {
          type = if isRemote then "remote" else "local";
          enabled = true;
        }
        // (lib.optionalAttrs isRemote { url = config.url; })
        // (lib.optionalAttrs (!isRemote) {
          command = [ config.command ] ++ (config.args or [ ]);
        })
        // (lib.optionalAttrs (config ? "env") { environment = config.env; })
        // (lib.optionalAttrs (config ? "headers") { headers = config.headers; })
      ) mcpServers;
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

        lsp = {
          nix = {
            command = [(lib.getExe pkgs.nixd)];
            extensions = ["nix"];
          };
        };

        formatter = {
          nix = {
            command = [(lib.getExe pkgs.nixfmt-rfc-style)];
            extensions = ["nix"];
          };
        };
      } // lib.optionalAttrs config.my.home.mcp.enable {
          mcp = lib.optionalAttrs (builtins.hasAttr "opencode" config.my.home.mcp.serverJsonContents) (
            if config.my.home.mcp.hub.enable then { opencode = {
              type = "local"; enabled = true;
              command = [ "mcp-remote-group" "opencode"]; }; }
            else config.my.home.mcp.serverJsonContents.opencode.mcpServers);

      }
    );
    "opencode/AGENTS.md".text =
      with prompts._snippet;
      with prompts.function; ''
      # AGENTS.md

      ## General

      ${charm}

      ## Language

      ${japanese.input}
      ${japanese.output}

      ## CLI tools

      ${tools}

      ## Security

      ${security}
    '';
  };

  programs = {
    bash.shellAliases = shellAliases;
    fish.shellAbbrs = shellAliases;
  };
}
