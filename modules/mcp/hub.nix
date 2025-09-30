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

  # Transform MCP server configurations into MCPJungle-compatible JSON format
  transformGroupConfig = groupName: groupConfig:
    lib.mapAttrs transformServerConfig groupConfig.mcpServers;
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

  # Generate MCPJungle-compatible JSON configurations for all enabled servers
  mcpJungleServerConfigs = lib.mapAttrs transformGroupConfig cfg.serverJsonContents;

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
    ];

    # Generate JSON configuration files for MCPJungle
    xdg.stateFile = let
      allServers = lib.foldl' (acc: group: acc // group) {} (lib.attrValues mcpJungleServerConfigs);
    in lib.mapAttrs' (
      serverName: serverConfig:
      lib.nameValuePair "mcpjungle/servers/${serverName}.json" {
        source = pkgs.writeText "${serverName}.json" (builtins.toJSON serverConfig);
      }
    ) allServers;

    systemd.user.services = {
      "mcpjungle-ready" = {
        Unit = {
          Description = "Ready for mcpjungle";
        };
        Service = {
          Type = "oneshot";
          ExecStart = "${pkgs.coreutils}/bin/mkdir -p ${config.xdg.stateHome}/mcpjungle";
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
          script = pkgs.writeShellScriptBin "setup-mcpjungle" ''
            # Register all server configurations with mcpjungle
            ${pkgs.findutils}/bin/find ${config.xdg.stateHome}/mcpjungle/servers -name "*.json" -exec ${mcpJungleWithRuntime}/bin/mcpjungle register -c {} \; || true
          '';
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
