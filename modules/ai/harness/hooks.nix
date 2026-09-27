# Hook scripts shared by codex and goose, one packaged script per event.
#
# retrieval-redirect is the PreToolUse hook that keeps both agents off raw
# read/grep calls. codegraph, zvec-grep and semble are already registered with
# both agents as MCP servers (see mcp.nix), so a raw cat/rg spends context on a
# weaker answer than the index returns with line numbers and call paths
# attached. Both agents speak the Claude hook dialect, so one script serves
# both: only the tool name in each plugin's matcher differs, and the script
# judges the leading command fragment instead of the tool name.
#
# refresh-index is the SessionStart counterpart: it runs the refresh command
# only where the index already governs the working directory the session was
# started in.
#
# The scripts live under hooks/ rather than inline so they stay readable and
# can be run directly against sample payloads; they are packaged here so both
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
          codegraph / zvec-grep / semble MCP tools to call instead. Anything the
          hook does not recognise, including searches confined to a single
          non-source file, passes through as an empty object, so it never becomes
          the reason a task stalls.
        '';
      };
    };

    refreshIndex = {
      package = lib.mkOption {
        type = lib.types.package;
        readOnly = true;
        default = pkgs.writeShellApplication {
          name = "refresh-index";
          text = lib.removePrefix "#!/usr/bin/env bash\n" (builtins.readFile ./hooks/refresh-index.sh);
        };
        defaultText = lib.literalExpression ''pkgs.writeShellApplication { name = "refresh-index"; ... }'';
        description = ''
          SessionStart hook wrapper that runs its command only when the index
          named by the first argument (the tool's own marker directory, resolved
          by walking up from the session's working directory) already covers the
          session. Skips otherwise, so an un-indexed tree pays no scan cost and
          never gets an index silently created under it.
        '';
      };
    };
  };
}
