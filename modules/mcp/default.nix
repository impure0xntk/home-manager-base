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

  allServers = {
    arxiv = {
      command = lib.getExe pkgs.mcp-server-arxiv;
      args = [ ];
    };
    desktop-commander = {
      command = lib.getExe pkgs.mcp-server-desktop-commander;
      args = [ ];
    };
    context7 = {
      # https://github.com/sst/opencode/issues/1244#issuecomment-3114688653
      url = "https://mcp.context7.com/sse";
    };
    git = {
      command = lib.getExe pkgs.mcp-server-git;
      args = [ ];
    };
    nixos = {
      command = lib.getExe pkgs.mcp-server-nixos;
      args = [ ];
    };
    excel = {
      command = lib.getExe pkgs.mcp-server-excel;
      args = [ "stdio" ];
    };
    playwright = {
      # Use ungoogled-chromium
      command = lib.getExe pkgs.mcp-server-playwright;
      args = [
        "--executable-path" "${lib.getExe pkgs.ungoogled-chromium}"
      ];
    };
    "pdf-reader" = {
      command = lib.getExe pkgs.mcp-server-pdf-reader;
      args = [ ];
    };
    quickchart = {
      command = lib.getExe pkgs.mcp-server-quickchart;
      args = [ ];
    };
    github = {
      # TODO: pass PAT
      url = "https://api.githubcopilot.com/mcp/";
    };
    "microsoft-docs-mcp" = {
      # FIXME: not work
      url = "https://learn.microsoft.com/api/mcp";
    };
    jetbrains = {
      command = lib.getExe pkgs.mcp-server-jetbrains;
      args = [ ];
    };
    serena = {
      command = lib.getExe pkgs.serena;
      args = [
        "start-mcp-server"
        "--enable-web-dashboard" "false"
      ];
    };
    atlassian = {
      # TODO: may be able to replace to "url"
      command = lib.getExe pkgs.mcp-server-remote;
      args = [
        "https://mcp.atlassian.com/v1/sse"
      ];
    };
    azure-devops = {
      command = lib.getExe pkgs.mcp-server-azure-devops;
      args = [
        "!! input your organization manually !!!"
      ];
    };
    searxng = {
      command = lib.getExe pkgs.mcp-server-searxng;
      env = {
        # TODO: refactor. now depends on local searxng instance.
        SEARXNG_INSTANCES = lib.concatStringsSep "," [
          "http://localhost:16060"
        ];
      };
    };
    fetch = {
      command = lib.getExe pkgs.mcp-server-fetch-zcaceres;
      args = [];
    };
    task-master = {
      command = "${pkgs.task-master}/bin/task-master-mcp";
      env = {
        # Use litellm
        OPENAI_BASE_URL = "http://localhost:${builtins.toString config.my.home.ai.litellm.port}";
      };
    };
    textlint = lib.optionalAttrs config.my.home.documentation.enable {
      command = "${config.my.home.documentation.executablePath}/bin/textlint";
      args = [
        "--mcp"
      ];
    };
    yfinance = {
      command = lib.getExe pkgs.mcp-server-yfinance;
      args = [];
    };
    investor-agent = {
      command = lib.getExe pkgs.mcp-server-investor-agent;
      args = [ ];
    };
  };

  # Generate a list of enabled servers for each configuration name
  serversForJson = lib.mapAttrs (
    configName: configValue:
      let
        # Selected servers from allServers
        selectedServers = lib.mapAttrs' (
          name: serverCfg:
            if serverCfg.enable then
              lib.nameValuePair name allServers.${name}
            else
              lib.nameValuePair "" null # Effectively remove disabled servers
        ) (lib.filterAttrs (n: _: n != "type" && n != "url" && n != "command" && n != "args") configValue);

        # Custom server definitions
        customServers = lib.optionalAttrs (configValue ? url && configValue.url != null) {
          ${configName} = {
            url = configValue.url;
          } // (lib.optionalAttrs (configValue ? command && configValue.command != null) {
            command = configValue.command;
          }) // (lib.optionalAttrs (configValue ? args && configValue.args != []) {
            args = configValue.args;
          });
        };

        # Servers specified by type
        typeServers = lib.optionalAttrs (configValue ? type && configValue.type != null) {
          ${configValue.type} = allServers.${configValue.type};
        };

        # Merge all servers
        allServersForConfig = selectedServers // customServers // typeServers;

        # Filter out empty entries
        filteredServers = lib.filterAttrs (n: v: n != "" && v != null) allServersForConfig;
      in
      {
        mcpServers = filteredServers;
      }
  ) cfg.servers;

  # Generate separate JSON files for each attrset
  mcpServerFiles = lib.mapAttrs (
    configName: configValue:
      pkgs.writeText "${configName}.json" (builtins.toJSON configValue)
  ) serversForJson;
in
{
  options.my.home.mcp = {
    enable = mkEnableOption "Enable MCP features";
    servers = mkOption {
      description = "Configuration for MCP servers.";
      type = with types; attrsOf (submodule {
        options = {
          # Type option to select from existing allServers
          type = mkOption {
            description = "Type of the server to enable from the predefined list.";
            type = nullOr (enum (lib.attrNames allServers));
            default = null;
          };
          # Options for custom server definitions
          url = mkOption {
            description = "URL of the custom MCP server.";
            type = nullOr str;
            default = null;
          };
          command = mkOption {
            description = "Command to start the custom MCP server.";
            type = nullOr str;
            default = null;
          };
          args = mkOption {
            description = "Arguments for the custom MCP server command.";
            type = listOf str;
            default = [];
          };
        } // lib.mapAttrs (
          name: _:
            mkOption {
              type = submodule {
                options = {
                  enable = mkEnableOption "the server";
                };
              };
              default = { enable = false; };
            }
        ) allServers;
      });
      default = {};
    };

    configFile = {
      path = mkOption {
        description = "Path where the MCP configuration files will be placed";
        type = path;
        default = "${config.xdg.configHome}/mcp";
      };
    };
    serverJsonSourcePaths = mkOption {
      description = "Paths to the generated JSON files for each server configuration attrset";
      type = attrsOf path;
      default = {};
    };
    serverJsonContents = mkOption {
      description = "Contents of the generated JSON files for each server configuration attrset";
      type = attrsOf (attrsOf anything);
      default = {};
    };
  };

  config = lib.mkIf config.my.home.mcp.enable {
    # For other tools
    # For vscode set "github.copilot.chat.mcp.discovery.enabled" to true.
    # Output JSON files for each attrset
    xdg.configFile = lib.mapAttrs' (
      configName: configFile:
      lib.nameValuePair "mcp/${configName}.json" {
        source = configFile;
      }
    ) mcpServerFiles;

    # Set the source paths for each server configuration JSON file
    my.home.mcp.serverJsonSourcePaths = mcpServerFiles;

    # Set the contents for each server configuration JSON file
    my.home.mcp.serverJsonContents = serversForJson;
  };
}
