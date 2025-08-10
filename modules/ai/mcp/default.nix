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
  cfg = config.my.home.ai.mcp;

  allServers = {
    git = {
      command = lib.getExe pkgs.mcp-server-git;
      args = [ ];
    };
    nixos = {
      command = lib.getExe pkgs.mcp-server-nixos;
      args = [ ];
    };
    "pdf-reader" = {
      command = lib.getExe pkgs.mcp-server-pdf-reader;
      args = [ ];
    };
    github = {
      url = "https://api.githubcopilot.com/mcp/";
    };
    "microsoft-docs-mcp" = {
      url = "https://learn.microsoft.com/api/mcp";
    };
    jetbrains = {
      command = lib.getExe pkgs.mcp-server-jetbrains;
      args = [ ];
    };
  };

  # Filter the servers that are enabled by the user (where value is true)
  # and map them to their full configuration from `allServers`.
  serversForJson = lib.mapAttrs' (
    name: serverCfg:
      if serverCfg.enable then
        lib.nameValuePair name allServers.${name}
      else
        lib.nameValuePair "" null # Effectively remove disabled servers
  ) cfg.servers;

  mcpServersFile = pkgs.writeText "mcp.json" (builtins.toJSON {
    mcpServers = serversForJson;
  });
in
{
  options.my.home.ai.mcp = {
    servers = mkOption {
      description = "Configuration for MCP servers.";
      type = with types; submodule {
        options = lib.mapAttrs (
          name: _:
            mkOption {
              type = submodule {
                options = {
                  enable = mkEnableOption "the server";
                };
              };
              default = { enable = true; };
            }
        ) allServers;
      };
      default = {};
    };

    stateDir = mkOption {
      description = "Directory where MCP state files are stored";
      type = path;
      default = "${config.xdg.stateHome}/mcp";
    };

    configFile = {
      source = mkOption {
        description = "Path to the MCP configuration file. Format is MCP official format. This is read-only";
        type = path;
        default = mcpServersFile;
        readOnly = true;
      };
      path = mkOption {
        description = "Path where the MCP configuration file will be placed";
        type = path;
        default = "${config.xdg.configHome}/mcp/mcp.json";
      };
    };
  };

  config = lib.mkIf config.my.home.ai.enable {
    home.activation."ready-for-mcp-state-base-dir" = ''
      mkdir -p ${cfg.stateDir}
    '';

    # For other tools
    # For vscode set "github.copilot.chat.mcp.discovery.enabled" to true.
    xdg.configFile."mcp/mcp.json".source = cfg.configFile.source;
  };
}
