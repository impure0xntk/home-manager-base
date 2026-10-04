# The fence command audit is the only thing standing between a shell call and
# the deny list the sandbox module declares, so assert the wiring rather than
# the script: both agents must run the same packaged hook, it must run after
# rtk's rewrite rather than before it, and jcode must reach it through the
# adapter that turns fence's JSON deny into its exit-code form.
#
# Order is asserted, not assumed. rtk rewrites `git commit` to `rtk git
# commit` and fence matches a rule as a literal prefix, so a hook listed first
# would ask fence about a command no agent runs. The audit normalises the
# launcher off, which makes either position give the same verdict -- and that
# is exactly why a silent reordering could not be caught by a functional test
# and has to be pinned here.
{ config, lib, ... }:
let
  harness = config.my.home.ai.harness;
  audit = lib.getExe harness.hooks.fenceAudit.package;

  hookCommandsOf =
    entries: lib.flatten (map (entry: map (hook: hook.command) entry.hooks) entries);

  codexPreToolUse = harness.plugins."nixos-reactor-harness-for-codex"."com.openai/hooks/hooks.json".hooks.PreToolUse;
  codexHookCommands = hookCommandsOf codexPreToolUse;

  rtkHookIndex = lib.elemIndexOf harness.codingAgentTools.rtk.package.outPath codexHookCommands;
  auditHookIndex = lib.elemIndexOf audit codexHookCommands;

  jcodeHooks = config.xdg.configFile."jcode/config.toml.orig";
  jcodeParsed = builtins.fromTOML (builtins.unsafeDiscardStringContext (builtins.readFile jcodeHooks.source));
  jcodePreTool = jcodeParsed.hooks.pre_tool or [ ];
  jcodePreToolTransform = jcodeParsed.hooks.pre_tool_transform or [ ];

  # jcode resolves decisions by exit code, so the adapter is what makes fence's
  # stdout JSON reachable at all. A hook wired without it would be read as allow.
  jcodeRunsAudit = lib.any (
    command: lib.hasInfix "jcode-pre-tool " command && lib.hasInfix "/fence-audit" command
  ) jcodePreTool;
in
{
  config = {
    my.home.ai.harness.enable = true;
    my.home.ai.harness.sandbox.enable = true;
    my.home.ai.codex.enable = true;
    my.home.ai.jcode.enable = true;
    my.home.ai.jcode.preToolUse.enable = true;

    assertions = [
      {
        assertion = lib.elem audit codexHookCommands;
        message = "codex must run the fence command audit on Bash calls, or the sandbox deny list never reaches a session that never enters a fence.";
      }
      {
        assertion = auditHookIndex != -1 && rtkHookIndex != -1 && auditHookIndex > rtkHookIndex;
        message = "the fence audit must run after the rtk rewrite: in front of it, fence is asked about `git commit` for a command rtk has not rewritten yet, and after it, about the rtk form -- either way the launcher has to be normalised off before the verdict means anything.";
      }
      {
        assertion = jcodeRunsAudit;
        message = "the jcode pre_tool gate must run the fence audit through its adapter, since jcode reads the decision from the exit code and not from hook JSON.";
      }
      {
        # retrieval-redirect is the gate that denies raw read and grep, and it is
        # deliberately off: this audit must never stand in for it. A deny list
        # that also denied reads would block the whole retrieval path.
        assertion = !lib.any (command: lib.hasInfix "/retrieval-redirect" command) jcodePreTool;
        message = "the jcode pre_tool gate must stay the fence audit alone; adding retrieval-redirect back to it denies every raw read and grep on this machine.";
      }
  ];
  };
}
