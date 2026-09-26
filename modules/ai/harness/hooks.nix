# PreToolUse hook that keeps codex and goose off raw read/grep calls.
#
# codegraph and zvec-grep are already registered with both agents as MCP
# servers (see mcp.nix), so a raw cat/rg spends context on a weaker answer than
# the index returns with line numbers and call paths attached. Both agents
# speak the Claude hook dialect, so one script serves both: only the tool name
# in each plugin's matcher differs, and the script judges the leading command
# fragment instead of the tool name.
#
# The script lives under hooks/ rather than inline so it stays readable and
# can be run directly against sample payloads; it is packaged here so both
# agent modules point at a single store path.

{ lib, pkgs, ... }:

{
  options.my.home.ai.harness.hooks = {
    retrievalRedirect = {
      package = lib.mkOption {
        type = lib.types.package;
        readOnly = true;
        default = pkgs.writeShellApplication {
          name = "retrieval-redirect";
          text = lib.removePrefix "#!/usr/bin/env bash\n" (builtins.readFile ./hooks/redirect-read-grep.sh);
          runtimeInputs = [ pkgs.jq ];
        };
        defaultText = lib.literalExpression ''pkgs.writeShellApplication { name = "retrieval-redirect"; ... }'';
        description = ''
          PreToolUse hook that denies read/grep-shaped tool calls and names the
          codegraph / zvec-grep MCP tools to call instead. Anything the hook does
          not recognise, including searches confined to a single non-source file,
          passes through as an empty object, so it never becomes the reason a
          task stalls.
        '';
      };
    };
  };
}
