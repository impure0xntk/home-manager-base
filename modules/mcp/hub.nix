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
  allServers = lib.flip lib.concatMapAttrs cfg.serverGroupFiles (groupName: groupConfig:
    groupConfig.configFiles or {}
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
      http://${cfg.hub.client.host}:${builtins.toString cfg.hub.client.port}/v0/groups/''${1:-input group}/mcp \
      --allow-http
  '';

  # Original server configuration files (will be transformed at runtime)
  # Use "cut -d, -fN" to separate name and path in shell script
  serverFiles = lib.mapAttrsToList (serverName: serverConfig:
    "${serverName},${serverConfig.configFile}"
  ) allServers;

  # Group to server mapping information
  groupMapping = lib.flip lib.mapAttrs cfg.serverGroupFiles (groupName: groupConfig:
    builtins.attrNames (groupConfig.configFiles or {})
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
    useSopsNix = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether using sops. If enabled start mcpjungle after sops-nix.service";
    };
    client = {
      enable = mkEnableOption "Enable MCP client for MCP Hub";
      host = mkOption {
        description = "Host of MCP hub";
        type = str;
        default = "127.0.0.1";
      };
      port = mkOption {
        description = "Port number of MCP hub client";
        type = number;
        default = 3001;
      };
    };
  };

  config = lib.mkIf config.my.home.mcp.hub.enable {
    # For CLI
    home.packages = [
      mcpJungleWithRuntime
    ] ++ lib.optionals cfg.hub.client.enable [
      mcp-serer-remote-group
    ];

    # Generate JSON configuration files for MCPJungle
    xdg.stateFile = builtins.listToAttrs [groupMappingFile];

    systemd.user.services = {
      "mcpjungle-ready" = {
        Unit = rec {
          Description = "Ready for mcpjungle";
          After = lib.optionals cfg.hub.useSopsNix [
            "sops-nix.service"
          ];
          Requires = lib.optionals cfg.hub.useSopsNix After;
        };
        Service = let script = pkgs.writeShellScriptBin "ready-for-mcpjungle" ''
          ${pkgs.coreutils}/bin/mkdir -p ${config.xdg.stateHome}/mcpjungle/servers
          rm -rf ${config.xdg.stateHome}/mcpjungle/mcp*.db 2>/dev/null || true
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
          jqFilter = pkgs.writeText "mcpjungle-transform.jq" ''
            . as $orig | {
              name: $name,
              description: "MCP server: \($name)",
              transport: (
                if $orig | has("url") then "streamable_http"
                elif $orig | has("command") then "stdio"
                else null end
              ),
              url: (if $orig | has("url") then $orig.url else null end),
              command: (if $orig | has("command") then $orig.command else null end),
              args: (if $orig | has("args") then $orig.args else null end),
              env: (if $orig | has("env") then $orig.env else null end),
              bearer_token: (if $orig | has("bearer_token") then $orig.bearer_token else null end)
            } | del(.[] | nulls)
          '';
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
              bash
            ];
            excludeShellChecks = [ "SC2016" ];
            text = ''
              echo "Waiting for mcpjungle to become available..."
              wait-for-it localhost:${builtins.toString cfg.hub.port} --strict --timeout=30

              echo "Processing server configurations..."
              echo "${lib.concatStringsSep "\n" serverFiles}" \
                | xargs -P4 -I{} bash -c '
                  server_name="$(echo {} | cut -d, -f1)"
                  server_file="$(echo {} | cut -d, -f2)"
                  echo "Processing server: $server_name"

                  # Transform config using jq
                  temp_file="$(mktemp /tmp/mcpjungle-server-$server_name-XXXXXX.json)"
                  jq -c --arg name "$server_name" -f ${jqFilter} "$server_file" > "$temp_file"

                  echo "Registering transformed config: $temp_file"
                  mcpjungle register -c "$temp_file" || true
                  rm -f "$temp_file"
                  '

              echo "Server registration complete"

              # Reset Tool Groups
              echo "Resetting existing groups..."
              { mcpjungle list groups 2>&1 | grep -E "^[0-9]+.*" | cut -d" " -f 2 \
                | xargs -I{} mcpjungle delete group {}; } || true

              # Create Tool Groups based on group mapping
              group_mapping_file="${config.xdg.stateHome}/mcpjungle/group-mapping.json"
              echo "Processing group mappings from $group_mapping_file"

              if [ -f "$group_mapping_file" ]; then
                # Get all group names
                groups=$(jq -r 'keys[]' "$group_mapping_file")

                # Process each group
                for group_name in $groups; do
                  echo "Creating group: $group_name"
                  # Get server names for this group
                  servers=$(jq -r --arg group "$group_name" '.[$group][]' "$group_mapping_file")
                  tools=()

                  # Collect enabled tools from each server in the group
                  for server_name in $servers; do
                    echo "  Checking tools from server: $server_name"
                    enabled_output=$({ mcpjungle list tools --server "$server_name" 2>&1 | grep "\[ENABLED\]" | cut -d" " -f 2; } || true)
                    if [ -n "$enabled_output" ]; then
                      readarray -O "''${#tools[@]}" -t tools <<< "$enabled_output"
                    fi
                  done

                  # Create group if there are tools
                  if [ ''${#tools[@]} -gt 0 ]; then
                    temp_json="/tmp/''${group_name}-group.json"
                    echo "    Creating group JSON: $temp_json"
                    echo "{\"name\": \"''${group_name}\", \"description\": \"Tool group for ''${group_name}\", \"included_tools\": [" > "$temp_json"
                    for tool in "''${tools[@]}"; do
                      echo "\"''${tool}\"," >> "$temp_json"
                    done
                    sed -i '$ s/,$/]}/' "$temp_json"
                    mcpjungle create group -c "$temp_json" || echo "Failed to create group $group_name"
                    rm -f "$temp_json"
                  else
                    echo "    No enabled tools found for group: $group_name"
                  fi
                done
              else
                echo "Group mapping file not found: $group_mapping_file"
              fi
              echo "Group setup complete"
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
