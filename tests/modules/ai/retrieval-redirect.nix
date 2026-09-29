# The retrieval redirect hook is the only thing standing between a codex or
# goose shell call and a raw cat/rg, so assert the wiring rather than the
# script: both plugins must run the same packaged hook.

{ config, lib, ... }:

let
  harness = config.my.home.ai.harness;
  redirect = lib.getExe harness.hooks.retrievalRedirect.package;
  hookCommands =
    entries: lib.flatten (map (entry: map (hook: hook.command) entry.hooks) entries);
  goosePreToolUse = harness.plugins."nixos-reactor-harness-for-goose"."hooks/hooks.json".hooks.PreToolUse;
  codexPreToolUse = harness.plugins."nixos-reactor-harness-for-codex"."com.openai/hooks/hooks.json".hooks.PreToolUse;
in
{
  config = {
    # Each agent module declares its plugin inside the matching `enable` gate, so
    # both have to be on before the wiring can be asserted.
    my.home.ai.harness.enable = true;
    my.home.ai.codex.enable = true;
    my.home.ai.goose.enable = true;

    assertions = [
      {
        assertion = lib.elem redirect (hookCommands goosePreToolUse);
        message = "goose must deny raw read/grep shell calls in favour of the codegraph and zvec-grep MCP tools.";
      }
      {
        assertion = lib.elem redirect (hookCommands codexPreToolUse);
        message = "codex must deny raw read/grep shell calls in favour of the codegraph and zvec-grep MCP tools.";
      }
    ];
  };
}
