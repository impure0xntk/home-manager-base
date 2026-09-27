{
  config,
  pkgs,
  lib,
  searchModelByRole,
  ...
}@args:

let
  cfg = config.my.home.ai;

  # The agent carrying a `main` command; the git worktree runner launches it.
  mainAgents = lib.filter (a: a.main != null) cfg.agents;
  mainAgent = if mainAgents == [ ] then null else lib.head mainAgents;
  mainAgentEnabled =
    mainAgent != null
    && lib.attrByPath [ mainAgent.name "enable" ] false cfg;
in
{
  imports = [
    # CLI agent configurations
    (import ./codex.nix (args // { inherit searchModelByRole; }))
    (import ./goose.nix (args // { inherit searchModelByRole; }))
    (import ./junie.nix (args // { inherit searchModelByRole; }))
    (import ./copilot-cli.nix (args // { inherit searchModelByRole; }))
    # Cline resolves no model declaratively, so it has no use for
    # `searchModelByRole` and takes no extra module arguments.
    ./cline.nix
    # Future agents can be added here:
    # (import ./agent-deck.nix (args // { inherit searchModelByRole; }))
    # (import ./other-agent.nix (args // { inherit searchModelByRole; }))
  ];

  options.my.home.ai.agents =
    with lib;
    with types;
    mkOption {
      description = "AI agent configuration for auto-approval rules and for picking the main agent";
      type = listOf (submodule {
        options = {
          name = mkOption {
            description = "Agent name (e.g., 'codex', 'goose', 'junie', 'copilot-cli')";
            type = str;
          };
          main = mkOption {
            description = "Command the git worktree runner starts for `git gtr new --ai` and `git gtr ai` (gtr.ai.default). Non-null marks this as the main agent, and at most one agent may do so. The value is handed to gtr as-is and follows its own spec: a built-in adapter name (claude, codex, copilot, gemini, opencode, ...) or any command on PATH, optionally with arguments. Paths and shell wrappers are rejected by gtr.";
            type = nullOr str;
            default = null;
            example = "codex";
          };
          autoApprovalRules = mkOption {
            description = ''
              Rules for automatically approving commands. Read by the git worktree
              runner, and by agents that expose the same shape natively: cline
              projects `allow` and `deny` onto CLINE_COMMAND_PERMISSIONS.
            '';
            type = listOf (submodule {
              options = {
                command = mkOption {
                  description = "Command pattern to match (e.g., 'ls', 'git *')";
                  type = str;
                };
                action = mkOption {
                  description = "Action to take: 'allow', 'deny', or 'ask'";
                  type = enum [ "allow" "deny" "ask" ];
                };
              };
            });
            default = [ ];
          };
        };
      });
    };

  config = {
    assertions = [
      {
        assertion = mainAgents == [ ] || builtins.length mainAgents == 1;
        message = "my.home.ai.agents: at most one agent may set main, but ${toString (builtins.length mainAgents)} do";
      }
      {
        assertion = mainAgent == null || mainAgentEnabled;
        message = "my.home.ai.agents: the main agent must also be enabled, set my.home.ai.${mainAgent.name}.enable = true";
      }
      {
        # gtr only runs a bare command from PATH; anything with a slash is a path it rejects.
        assertion = mainAgent == null || !lib.hasInfix "/" mainAgent.main;
        message = "my.home.ai.agents: the main agent command must be a command on PATH, not a path (gtr rejects '/'): ${mainAgent.main}";
      }
    ];

    programs.vscode.profiles.default = {
      extensions = (pkgs.nix4vscode.forVscode [ ]);
    };

    programs.git.settings.gtr =
      {
      }
      // lib.optionalAttrs (mainAgent != null) {
        ai = {
          default = mainAgent.main;
        };
      };
  };
}
