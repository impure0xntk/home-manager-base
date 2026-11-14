# rtk: output condensing tool for coding agents.
#
# Declared here as a `mkDefault` contribution to `codingAgentTools`, so a machine
# config can remove it (`codingAgentTools = lib.attrWithout [ "rtk" ] ...`) or
# override its package/prompt without touching this file.
{ config, lib, pkgs, ... }:
let
  cfg = config.my.home.ai.harness;
  prompt = builtins.readFile ./RTK.md;
in
{
  config = lib.mkIf cfg.enable {
    my.home.ai.harness.codingAgentTools = lib.mkDefault {
      rtk = {
        package = pkgs.rtk;
        prompt = prompt;
      };
    };
  };
}
