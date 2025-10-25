# Need mcp-server-nix as overlays, NOT module.
# Because module generates json file on build, so it's not possible to use it as Nix home-manager configuration.

{
  config,
  pkgs,
  lib,
  ...
}@args:
with lib;
with lib.types;
let
  cfg = config.my.home.mcp;

  allServers = import ./preset-servers.nix args;

  # Generate server configurations for each group
  serverGroupFiles = lib.mapAttrs (
    configName: configValue:
      let
        presetServers = lib.mapAttrs' (name: serverCfg:
          if serverCfg.enable then
            let
              baseConfig = allServers.${name};
              mergedConfig = baseConfig // lib.filterAttrs (_: v: v != null) {
                command = serverCfg.command;
                args = serverCfg.args;
                env = serverCfg.env;
              };
            in
            lib.nameValuePair name {
              configFile = pkgs.writeText "${configName}-${name}.json" (builtins.toJSON mergedConfig);
            }
          else
            lib.nameValuePair "" null
        ) configValue.presetServers;

        customServers = lib.mapAttrs' (name: serverCfg:
          lib.nameValuePair name {
            configFile = serverCfg.configFile;
          }
        ) configValue.customServers;
      in
      {
        configFiles = lib.mapAttrs (_: v: { configFile = v.configFile; }) (customServers // presetServers);
      }
  ) cfg.servers;

in
{
  options.my.home.mcp = {
    enable = mkEnableOption "Enable MCP features";
    servers = mkOption {
      description = "Configuration for MCP servers. Separate preset and custom server configurations.";
      type = with types; attrsOf (submodule {
        options = {
          presetServers = mkOption {
            description = "Attribute set of preset server configurations";
            type = attrsOf (submodule {
              options = {
                enable = mkOption {
                  type = bool;
                  default = true;
                  description = "Whether to enable this server";
                };
                command = mkOption {
                  type = nullOr str;
                  default = null;
                  description = "Override the preset command";
                };
                args = mkOption {
                  type = nullOr (listOf str);
                  default = null;
                  description = "Override the preset arguments";
                };
                env = mkOption {
                  type = nullOr attrs;
                  default = null;
                  description = "Override the environment variables";
                };
              };
            });
            default = {};
            example = {
              git.enable = true;
              nixos = {
                enable = true;
                args = ["--verbose"];
              };
            };
          };
          customServers = mkOption {
            description = "Custom server configurations by name";
            type = attrsOf (submodule {
              options = {
                configFile = mkOption {
                  type = path;
                  description = "Path to JSON configuration file";
                };
              };
            });
            default = {};
            example = {
              myserver = {
                configFile = ./custom-server.json;
              };
            };
          };
        };
      });
      default = {};
    };

    serverGroupFiles = mkOption {
      description = "Contents of the generated JSON files for each server configuration";
      type = attrsOf attrs;
      default = {};
    };
  };

  imports = [
    ./hub.nix
  ];

  config = lib.mkIf config.my.home.mcp.enable {
    # For other tools
    # For vscode set "github.copilot.chat.mcp.discovery.enabled" to true.

    # Set the source paths for each server configuration JSON file
    my.home.mcp = {
      inherit serverGroupFiles;
    };
  };
}

