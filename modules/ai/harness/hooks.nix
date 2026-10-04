# Hook scripts shared by codex and goose, one packaged script per event.
#
# retrieval-redirect is the PreToolUse hook that keeps both agents off raw
# read/grep calls. codegraph and zvec-grep are already registered with both
# agents as MCP servers (see mcp.nix), so a raw cat/rg spends context on a
# weaker answer than the index returns with line numbers and call paths
# attached. Both agents speak the Claude hook dialect, so one script serves
# both: only the tool name in each plugin's matcher differs, and the script
# judges the leading command fragment instead of the tool name.
#
# refresh-index is the SessionStart counterpart: it runs the refresh command
# only where the index already governs the working directory the session was
# started in.
#
# The scripts under hooks/ are packaged here so both agent modules point at a
# single store path. `writeShellApplication` prepends its runtimeInputs to an
# inherited PATH, so anything a script shells out to has to be declared there:
# a hook that finds its own tools only by luck of the launching agent's
# environment works in a login shell and drops the prompt or the tool input in
# a hook process, which is the only shape a hook is ever run in.

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
          runtimeInputs = [
            pkgs.jq
            pkgs.coreutils
          ];
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

    refreshIndex = {
      package = lib.mkOption {
        type = lib.types.package;
        readOnly = true;
        default = pkgs.writeShellApplication {
          name = "refresh-index";
          text = lib.removePrefix "#!/usr/bin/env bash\n" (builtins.readFile ./hooks/refresh-index.sh);
          runtimeInputs = [ pkgs.coreutils ];
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

    fenceAudit = {
      package = lib.mkOption {
        type = lib.types.package;
        readOnly = true;
        default = pkgs.writeShellApplication {
          name = "fence-audit";
          text = lib.removePrefix "#!/usr/bin/env bash\n" (builtins.readFile ./hooks/fence-audit.sh);
          runtimeInputs = [
            pkgs.jq
            pkgs.coreutils
            pkgs.fence
          ];
        };
        defaultText = lib.literalExpression ''pkgs.writeShellApplication { name = "fence-audit"; ... }'';
        description = ''
          PreToolUse hook asks fence the same command question its
          sandbox profile already answers at runtime, so an agent that
          never enters a fence session still meets the command deny
          list. The command is normalised first: fence matches a rule
          as a literal prefix, so `rtk`, `rtk proxy`, `RTK_DISABLED=1`,
          `env`, `command` and `exec` are peeled off or the harness
          becomes a bypass of the policy it enforces.

          Deny answers carry fence's own reason. A fence that cannot be
          run, or whose settings do not load, is answered allow: this
          hook must not become the reason a session stalls.
        '';
      };
    };

    translatePrompt = {
      package = lib.mkOption {
        type = lib.types.package;
        readOnly = true;
        default = pkgs.writeShellApplication {
          name = "translate-prompt";
          text = lib.removePrefix "#!/usr/bin/env bash\n" (builtins.readFile ./hooks/translate-prompt.sh);
          runtimeInputs = [
            pkgs.jq
            pkgs.coreutils
            pkgs.translate-shell
          ];
        };
        defaultText = lib.literalExpression ''pkgs.writeShellApplication { name = "translate-prompt"; ... }'';
        description = ''
          UserPromptSubmit hook wrapper that translates the prompt using an external tool
          (e.g., Google Translate). The translation is done by running a command
          that reads the prompt from standard input, translates it to English,
          and writes the translated prompt back to standard output. This hook can be
          used to automatically translate prompts before they are submitted for
          processing.
        '';
      };
    };

  };
}
