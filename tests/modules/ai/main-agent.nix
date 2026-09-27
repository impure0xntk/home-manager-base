# my.home.ai.agents (main) is the single source of truth for the command the git
# worktree runner starts, so assert gtr.ai.default is taken from it verbatim.
{
  config,
  ...
}:

{
  config = {
    my.home.ai.codex.enable = true;
    my.home.ai.agents = [
      {
        name = "codex";
        main = "codex";
      }
    ];

    assertions = [
      {
        assertion = config.programs.git.settings.gtr.ai.default == "codex";
        message = "gtr.ai.default must be the command from the agent carrying my.home.ai.agents.*.main";
      }
    ];
  };
}
