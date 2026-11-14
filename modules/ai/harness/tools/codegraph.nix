# codegraph: structural code Q&A tool exposed to coding agents.
#
# Declared here as a `mkDefault` contribution to `codingAgentTools`, so a machine
# config can remove it (`codingAgentTools = lib.attrWithout [ "codegraph" ] ...`)
# or override its package/prompt without touching this file.
{ config, lib, pkgs, ... }:
let
  cfg = config.my.home.ai.harness;
  createWrappedPackage = package: envVars: pkgs.writeShellApplication {
    name = package.meta.mainProgram;
    runtimeInputs = [ package ];
    runtimeEnv = envVars;
    text = ''
      exec ${lib.getExe package} "$@"
    '';
  };
  prompt = builtins.readFile ./CODEGRAPH.md;
in
{
  config = lib.mkIf cfg.enable {
    my.home.ai.harness.codingAgentTools = lib.mkDefault {
      codegraph = rec {
        package = createWrappedPackage pkgs.codegraph {
          CODEGRAPH_TELEMETRY = "0";
          DO_NOT_TRACK = "1";
        };
        inherit prompt;
        mcpServer = {
          command = lib.getExe package;
          args = [ "serve" "--mcp" ];
        };
      };
    };
  };
}
