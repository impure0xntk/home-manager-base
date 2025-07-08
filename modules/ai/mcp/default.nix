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

  # TODO: ensure under 128 tools for VS Code.
  mcpServers = {
    # TODO: proxy
/*     context7 = {
      command = lib.getExe pkgs.context7-mcp;
    }; */
    fetch = {
      command = lib.getExe pkgs.mcp-server-fetch;
    };
    filesystem = {
      command = lib.getExe pkgs.mcp-server-filesystem;
      args = [
        config.home.homeDirectory
      ];
    };
    git = {
      command = lib.getExe pkgs.mcp-server-git;
    };
    memory = {
      command = lib.getExe pkgs.mcp-server-memory;
      env = {
        "MEMORY_FILE_PATH" = "${cfg.stateDir}/memory.json";
      };
    };
    sequential-thinking = {
      command = lib.getExe pkgs.mcp-server-sequential-thinking;
    };
    nixos = {
      command = lib.getExe pkgs.mcp-server-nixos;
    };
    # FIXME: " tool parameters array type must have items"
    # https://github.com/microsoft/vscode/issues/248810#issuecomment-2877319893
/*     quickchart = {
      command = lib.getExe pkgs.mcp-server-quickchart;
    }; */
/*     task-master = {
      command = lib.getExe pkgs.mcp-server-task-master;
    }; */
    pdf-reader = {
      command = lib.getExe pkgs.mcp-server-pdf-reader;
    };
    github = {
      url = "https://api.githubcopilot.com/mcp/";
    };
/*     doc = {
      command = lib.getExe pkgs.mcp-server-doc;
    }; */
/*     atlassian-remote = {
      command = lib.getExe pkgs.mcp-server-remote;
      args = [
        "https://mcp.atlassian.com/v1/sse"
      ];
    }; */
/*     jetbrains = {
      command = lib.getExe pkgs.mcp-server-jetbrains;
    }; */
/*     azure-devops = {
      command = lib.getExe pkgs.mcp-server-azure-devops;
    }; */

    # Use project root, not global.
/*     lsp = {
      command = lib.getExe pkgs.mcp-server-lsp;
    }; */
/*     excel = { # not work on nix because create log file at Nix drv dir. src/excel_mcp/server.py:57
      command = lib.getExe pkgs.mcp-server-excel;
    }; */
  };
  mcpServersFile = pkgs.writeText "mcp.json" (builtins.toJSON {
    mcpServers = cfg.servers;
  });
in
{
  options.my.home.ai.mcp = {
    servers = mkOption {
      description = "MCP server configuration";
      type = attrs;
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
      };
      path = mkOption {
        description = "Path where the MCP configuration file will be placed";
        type = path;
        default = "${config.xdg.configHome}/mcp/mcp.json";
      };
    };
  };
  config = lib.mkIf config.my.home.ai.enable {
    my.home.ai.mcp.servers = mcpServers;

    home.activation."ready-for-mcp-state-base-dir" = ''
      mkdir -p ${cfg.stateDir}
    '';

    # For other tools
    # For vscode set "github.copilot.chat.mcp.discovery.enabled" to true.
    xdg.configFile."mcp/mcp.json".source = cfg.configFile.source;
  };
}
