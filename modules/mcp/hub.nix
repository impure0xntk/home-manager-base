# Need mcp-server-nix as overlays, NOT module.
# Because module generates json file on build, so it's not possible to use it as Nix home-manager configuration.

{
  config,
  pkgs,
  lib,
  ...
}:
with lib;
with lib.types;
let
  cfg = config.my.home.mcp;
  # All servers in flat structure to prevent duplicate registration
  allServers = lib.flip lib.concatMapAttrs cfg.serverJsonContents (groupName: groupConfig:
    groupConfig.mcpServers or {}
  );
  mcpJungleWithRuntime = pkgs.symlinkJoin {
    name = pkgs.mcpjungle.pname;
    paths = with pkgs; [
      mcpjungle

      # node
      nodejs
      # python
      python3
      uv
      # go
      go
    ];
    nativeBuildInputs = with pkgs; [
      makeWrapper
    ];
    postBuild = ''
      wrapProgram $out/bin/mcpjungle \
        --add-flags "--registry http://127.0.0.1:${builtins.toString cfg.hub.port}"
    '';
  };

  mcp-serer-remote-group = pkgs.writeShellScriptBin "mcp-remote-group" ''
    ${pkgs.mcp-server-remote}/bin/mcp-remote \
      http://127.0.0.1:${builtins.toString cfg.hub.port}/v0/groups/''${1:-input group}/mcp \
      --allow-http
  '';

  # Transform MCP server configurations into MCPJungle-compatible JSON format
  transformServerConfig = serverName: serverConfig:
    let
      baseConfig = {
        name = serverName;
        description = "MCP server: ${serverName}";
      };
    in
    if serverConfig ? url then
      baseConfig // {
        transport = "streamable_http";
        url = serverConfig.url;
      } // (lib.optionalAttrs (serverConfig ? bearer_token) {
        bearer_token = serverConfig.bearer_token;
      })
    else if serverConfig ? command then
      baseConfig // {
        transport = "stdio";
        command = serverConfig.command;
      } // (lib.optionalAttrs (serverConfig ? args) {
        args = serverConfig.args;
      }) // (lib.optionalAttrs (serverConfig ? env) {
        env = serverConfig.env;
      })
    else
      baseConfig;

  # Generate MCPJungle-compatible JSON configurations for all enabled servers in flat structure
  serverFiles = lib.mapAttrsToList (serverName: serverConfig:
    lib.nameValuePair "mcpjungle/servers/${serverName}.json" {
      text = builtins.toJSON (transformServerConfig serverName serverConfig);
    }
  ) allServers;

  # Group to server mapping information
  groupMapping = lib.flip lib.mapAttrs cfg.serverJsonContents (groupName: groupConfig:
    builtins.attrNames (groupConfig.mcpServers or {})
  );

  # Generate group mapping file
  groupMappingFile = lib.nameValuePair "mcpjungle/group-mapping.json" {
    text = builtins.toJSON groupMapping;
  };
in
{
  options.my.home.mcp.hub = {
    enable = mkEnableOption "Whether to enable MCP hub (mcpjungle).";
    port = mkOption {
      description = "Port number of MCP hub";
      type = number;
      default = 3001;
    };
  };

  config = lib.mkIf config.my.home.mcp.hub.enable {
    # For CLI
    home.packages = [
      mcpJungleWithRuntime
      mcp-serer-remote-group
    ];

    # Generate JSON configuration files for MCPJungle
    xdg.stateFile = builtins.listToAttrs ([groupMappingFile] ++ serverFiles);

    systemd.user.services = {
      "mcpjungle-ready" = {
        Unit = {
          Description = "Ready for mcpjungle";
        };
        Service = let script = pkgs.writeShellScriptBin "ready-for-mcpjungle" ''
          ${pkgs.coreutils}/bin/mkdir -p ${config.xdg.stateHome}/mcpjungle/servers
          rm -rf ${config.xdg.stateHome}/mcpjungle/mcp.db 2>/dev/null || true
        '';
        in {
          Type = "oneshot";
          ExecStart = "${script}/bin/ready-for-mcpjungle";
        };
        Install = {
          WantedBy = [ "default.target" ];
        };
      };

      "mcpjungle" = {
        Unit = rec {
          Description = "mcpjungle server";
          StartLimitIntervalSec = "120";
          StartLimitBurst = "5";
          After = [
            "mcpjungle-ready.service"
          ];
          Requires = After;
        };
        Service = {
          WorkingDirectory = "${config.xdg.stateHome}/mcpjungle";
          ExecStart = "${pkgs.mcpjungle}/bin/mcpjungle start --port ${builtins.toString cfg.hub.port}";
          Environment = lib.optionals config.my.home.networks.proxy.enable [
            "https_proxy=${config.my.home.networks.proxy.default}"
            "HTTPS_PROXY=${config.my.home.networks.proxy.default}"
          ];
          Restart = "on-failure";
          RestartSec = 5;
          StateDirectory = "mcpjungle";
          RuntimeDirectory = "mcpjungle";
          RuntimeDirectoryMode = "0755";
          StandardOutput = "journal";
          StandardError = "journal";
        };
        Install = {
          WantedBy = [ "default.target" ];
        };
      };
      "mcpjungle-post-setup" = {
        Unit = rec {
          Description = "Post setup for mcpjungle";
          Requires = [
            "mcpjungle.service"
          ];
          After = Requires;
        };
        Service = let
          script = pkgs.writeShellApplication {
            name = "setup-mcpjungle";
            runtimeInputs = with pkgs; [
              gnugrep
              gnused
              coreutils
              findutils
              jq
              mcpJungleWithRuntime
              wait-for-it
            ];
            text = ''
              wait-for-it localhost:${builtins.toString cfg.hub.port} --strict --timeout=30

              # Register all server configurations with mcpjungle
              { find ${config.xdg.stateHome}/mcpjungle/servers -name "*.json" -print0 \
                | xargs -0 -P4 -I{} mcpjungle register -c {}; } || true

              # Reset Tool Groups
              { mcpjungle list groups 2>&1 | grep -E "^[0-9]+.*" | cut -d" " -f 2 \
                | xargs -I{} mcpjungle delete group {}; } || true

              # Create Tool Groups based on group mapping
              group_mapping_file="${config.xdg.stateHome}/mcpjungle/group-mapping.json"

              if [ -f "$group_mapping_file" ]; then
                # Get all group names
                groups=$(jq -r 'keys[]' "$group_mapping_file")

                # Process each group
                for group_name in $groups; do
                  # Get server names for this group
                  servers=$(jq -r --arg group "$group_name" '.[$group][]' "$group_mapping_file")
                  tools=()

                  # Collect enabled tools from each server in the group
                  for server_name in $servers; do
                    enabled_output=$({ mcpjungle list tools --server "$server_name" 2>&1 | grep "\[ENABLED\]" | cut -d" " -f 2; } || true)
                    if [ -n "$enabled_output" ]; then
                      readarray -O "''${#tools[@]}" -t tools <<< "$enabled_output"
                    fi
                  done

                  # Create group if there are tools
                  if [ ''${#tools[@]} -gt 0 ]; then
                    temp_json="/tmp/''${group_name}-group.json"
                    echo "{\"name\": \"''${group_name}\", \"description\": \"Tool group for ''${group_name}\", \"included_tools\": [" > "''${temp_json}"
                    for tool in "''${tools[@]}"; do
                      echo "\"''${tool}\"," >> "''${temp_json}"
                    done
                    sed -i '$ s/,$/]}/' "$temp_json"
                    mcpjungle create group -c "$temp_json" || true
                    rm -f "$temp_json"
                  fi
                done
              fi
            '';
          };
      in {
        ExecStart = "${script}/bin/setup-mcpjungle";
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
      };
    };
  };
}
