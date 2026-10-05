# junie consumes nothing through home-manager's module system, so the generated
# files are the only thing worth asserting. What is pinned here is every place
# junie diverges from codex, goose and qwen-code, and each of which is a place
# a future edit can silently lose the harness wiring:
#
# - everything lives under `$XDG_CONFIG_HOME/junie` and is reached through
#   `JUNIE_CONFIG_LOCATION`, since `$JUNIE_HOME` is the data home that
#   home-manager does not manage.
# - hooks are a matcher-entry list, not a list of command strings, and the
#   shell tool is matched as `Bash`.
# - project-local `hooks` are ignored by junie for safety, so the module's
#   wrapper has to pass the generated file explicitly and turn the default
#   locations off, or none of these hooks would ever run.
# - MCP servers live in `mcp.json` under `mcpServers` with no timeout field.
# - the subagent profile is YAML frontmatter, and `permissionMode` is the key
#   junie reads for what the shared `sandbox_mode` means elsewhere.
{
  config,
  lib,
  ...
}:
let
  harness = config.my.home.ai.harness;

  # store paths inside generated files come back in string context, which
  # `fromJSON` refuses, so the context is dropped before parsing.
  read = path: builtins.unsafeDiscardStringContext (builtins.readFile path);

  # `?` takes a literal attrpath, not a variable, so the key is passed to
  # `builtins.hasAttr`.
  hasJunieConfigFile = name: builtins.hasAttr name config.xdg.configFile;

  # Activation entries are named, not written, so presence is what is
  # asserted; reading a script body would only prove one entry's content.
  activationNames = builtins.attrNames config.home.activation;

  junieConfig = builtins.fromJSON (read config.xdg.configFile."junie/config.json".source);
  junieMcp = builtins.fromJSON (read config.xdg.configFile."junie/mcp/mcp.json".source);

  hooks = junieConfig.hooks or { };
  preToolEntries = hooks.PreToolUse or [ ];
  preToolCommands = lib.concatMap (entry: map (hook: hook.command) (entry.hooks or [ ])) preToolEntries;
  sessionStartCommands = lib.concatMap (entry: map (hook: hook.command) (entry.hooks or [ ])) (hooks.SessionStart or [ ]);

  runsRetrievalGate = lib.any (command: lib.hasInfix "/retrieval-redirect" command) preToolCommands;
  runsFenceAudit = lib.any (command: lib.hasInfix "/fence-audit" command) preToolCommands;
  runsRtkRewrite = lib.any (command: lib.hasInfix "/rtk" command) preToolCommands;

  mcpServerNames = builtins.attrNames junieMcp.mcpServers;
  mcpServers = builtins.attrValues junieMcp.mcpServers;

  workerAgent = read config.xdg.configFile."junie/agents/worker.md".source;
  reviewerAgent = read config.xdg.configFile."junie/agents/reviewer.md".source;

  # The wrapper is the only place the generated file can be pointed at. Its
  # environment is asserted by reading the built script straight off the
  # package, since `home.packages` carries no identity a test can select on.
  wrapperScript = read (config.my.home.ai.junie.package + "/bin/junie");

  # Split into lines so a single `export KEY='value'` can be checked for its
  # key and its value without building a regex out of a store path.
  wrapperEnvLines = lib.splitString "\n" wrapperScript;

  # The `export KEY='value'` line for `name`, or "" when the wrapper does not
  # set it. Compared as a whole line rather than by substring, because
  # `lib.hasInfix` compiles its argument into a regex and the evaluator refuses
  # to build one that interpolates a store path. `lib.head` throws on an empty
  # list, so the emptiness is branched on explicitly.
  wrapperExport = name:
    let matches = lib.filter (line: lib.hasPrefix "export ${name}='" line) wrapperEnvLines;
    in if matches == [ ] then "" else lib.head matches;
in
{
  config = {
    my.home.ai = {
      enable = true;
      harness.enable = true;
      # The fence audit hook is wired under `harness.sandbox.enable`, which
      # defaults to false, so without this the assertions below would be
      # asserting against a configuration no machine actually uses.
      harness.sandbox.enable = true;

      junie = {
        enable = true;
        # Declared so the wrapper-environment assertions below are about what
        # the module derives and adds, not about a literal this test repeats.
        environmentVariables.JUNIE_TEST_SENTINEL = "1";
      };

      subagents = {
        # Off by default, and the whole point of these assertions: the profile
        # files only exist once sub-agents are enabled and `junie` is a target.
        enable = true;

        profiles = {
          worker = {
            description = "Scoped implementation work.";
            instructions = "Implement change. Do not switch scope on your own.";
            model_role = "edit";
            reasoning_effort = "high";
            sandbox_mode = "workspace-write";
          };
          reviewer = {
            description = "Read-only review.";
            instructions = "Review diff and report findings. Do not edit files.";
            model_role = "chat";
            reasoning_effort = "low";
            sandbox_mode = "read-only";
          };
        };
      };

      providers = [
        {
          name = "junie-test-local";
          url = "http://localhost:1143";
          isLocal = true;
          models = [
            {
              model = "chat-model";
              roles = [ "chat" ];
            }
            {
              model = "edit-model";
              roles = [ "edit" ];
            }
          ];
        }
      ];

      # Declared under `harness`, not directly on `my.home.ai`: that is where
      # the option lives, and where the module reads it from.
      harness.prompts.review = {
        text = "Review the staged diff and report findings.";
      };
    };

    assertions = [
      {
        assertion = hasJunieConfigFile "junie/config.json";
        message = "junie's configuration must be generated under the XDG config home.";
      }
      {
        assertion = hasJunieConfigFile "junie/mcp/mcp.json";
        message = "the harness MCP registry must reach junie as an mcp.json.";
      }
      {
        # `$JUNIE_HOME` is the XDG *data* home, so both files the module writes
        # there have to be installed by activation rather than linked. Each
        # entry is checked on its own: a single combined pattern would pass on
        # one of the two being dropped.
        assertion = builtins.elem "installJunieGlobalGuidelines" activationNames
          && builtins.elem "installJunieMcpConfig" activationNames;
        message = "the Junie home documents must be installed by activation, since home-manager does not manage the data home.";
      }
      {
        assertion = wrapperExport "JUNIE_CONFIG_LOCATION"
          == "export JUNIE_CONFIG_LOCATION='${config.xdg.configFile."junie/config.json".source}'";
        message = "the wrapper must pass the generated config.json through JUNIE_CONFIG_LOCATION, because junie ignores project-local hooks.";
      }
      {
        assertion = wrapperExport "JUNIE_CONFIG_DEFAULT_LOCATIONS" == "export JUNIE_CONFIG_DEFAULT_LOCATIONS='false'";
        message = "the wrapper must disable the default config locations, so a hand-written user config cannot merge on top of the generated one.";
      }
      {
        assertion = wrapperExport "JUNIE_HOME" == "export JUNIE_HOME='${config.xdg.dataHome}/junie'";
        message = "the wrapper must point JUNIE_HOME at the XDG data home, which is where junie keeps AGENTS.md and mcp/mcp.json.";
      }
      {
        # A declared key has to reach the wrapper, or the option is decorative.
        assertion = lib.all (name: wrapperExport name == "export ${name}='1'")
          (lib.attrNames config.my.home.ai.junie.environmentVariables);
        message = "every my.home.ai.junie.environmentVariables entry must be set on the wrapper.";
      }
      {
        # Without this the agent phones home, and the Nix store is the only
        # thing that decides which version runs.
        assertion = wrapperExport "JUNIE_SHARE_ANONYMOUS_STATISTICS" == "export JUNIE_SHARE_ANONYMOUS_STATISTICS='false'";
        message = "the wrapper must keep anonymous statistics off.";
      }
      {
        assertion = junieConfig.brave == true && junieConfig.auto-update == false;
        message = "junie must keep brave mode on and the self-updater off, so the Nix-managed package is the one that runs.";
      }
      {
        # The harness prompts are Markdown with a `description` frontmatter,
        # which is exactly junie's slash-command format, so the prompts
        # directory has to be declared rather than copied.
        assertion = junieConfig."command-locations" == [ harness.promptsDir ];
        message = "the harness prompts must be reachable as junie slash commands through command-locations.";
      }
      {
        assertion = junieConfig."agent-locations" == [ "${config.xdg.configHome}/junie/agents" ];
        message = "the generated subagent profiles must be declared through agent-locations.";
      }
      {
        assertion = !(junieConfig ? "skill-locations");
        message = "junie must not declare skill-locations: ~/.agents/skills already holds every harness skill, so a second directory would register each name twice.";
      }
      {
        assertion = !(junieConfig ? "guidelines-location");
        message = "guidelines-location replaces the project guideline lookup, so setting it would drop the repository's own AGENTS.md.";
      }
      {
        # matcher entries carry a tool name, not a command, and every hook
        # under them must be `type = "command"` with a timeout.
        assertion = preToolEntries != [ ]
          && lib.all (entry: entry ? matcher) preToolEntries
          && lib.all (entry: lib.all (hook: hook.type == "command" && hook ? command && hook ? timeout) (entry.hooks or [ ])) preToolEntries;
        message = "every PreToolUse hook must be a matcher entry whose hooks are command hooks with a timeout.";
      }
      {
        assertion = lib.all (entry: entry.matcher == "Bash") preToolEntries;
        message = "junie matches PreToolUse against the tool name, and only the Bash tool carries a command a hook can judge.";
      }
      {
        assertion = runsFenceAudit;
        message = "the junie PreToolUse gate must run the sandbox fence audit.";
      }
      {
        assertion = runsRetrievalGate;
        message = "the junie PreToolUse gate must run retrieval-redirect, or upstream would turn raw reads and greps back on.";
      }
      {
        assertion = runsRtkRewrite;
        message = "the junie PreToolUse gate must run the rtk rewrite, or every command would ship uncondensed.";
      }
      {
        # Junie's documented `PreToolUse` output is top-level `decision` plus
        # `updatedInput`. It has no `hookSpecificOutput` field at this event, so
        # a hook emitting the Claude envelope produces output Junie parses into
        # nothing and the rewrite is silently dropped. rtk is only ever handed
        # the Claude envelope, so the translation is this hook's own job.
        # Matched without the quotes: inside the generated JSON the embedded jq
        # filter carries escaped quotes, so a substring spanning them would be
        # asserting on the JSON encoding rather than on the hook's behaviour.
        assertion = lib.any (command: lib.hasInfix "updatedInput: {command:" command) preToolCommands
          && lib.any (command: lib.hasInfix "decision:" command) preToolCommands
          && !(lib.any (command: lib.hasInfix "hookSpecificOutput.permissionDecision =" command) preToolCommands);
        message = "the junie rtk hook must answer in Junie's own PreToolUse shape, top-level decision plus updatedInput, not the Claude hookSpecificOutput envelope.";
      }
      {
        assertion = !(lib.any (command: lib.hasInfix "translate-prompt" command) preToolCommands)
          && !(hooks ? UserPromptSubmit);
        message = "translate-prompt must stay unwired: junie's UserPromptSubmit output has no field that replaces the prompt, so a rewritten .prompt parses into nothing.";
      }
      {
        # refresh-index is the SessionStart counterpart, and it skips itself
        # outside an indexed tree, so the command list is what is asserted.
        assertion = lib.any (command: lib.hasInfix ".codegraph" command) sessionStartCommands;
        message = "the junie SessionStart hook must refresh the codegraph index where it already governs the tree.";
      }
      {
        assertion = lib.any (command: lib.hasInfix ".zvec-grep" command) sessionStartCommands;
        message = "the junie SessionStart hook must refresh the zvec-grep index where it already governs the tree.";
      }
      {
        assertion = builtins.hasAttr "mcpServers" junieMcp && !(builtins.hasAttr "servers" junieMcp);
        message = "junie reads its MCP file under the mcpServers key.";
      }
      {
        assertion = lib.all (name: name == "harness-tools-core" || name == harness.mcp.name) mcpServerNames;
        message = "junie must register exactly the harness MCP registry.";
      }
      {
        # Junie's bean has no per-server timeout, so writing the registry's
        # value in would be a key the agent silently ignores.
        assertion = lib.all (server: server ? command && server ? args && server ? enabled && !(server ? timeout)) mcpServers;
        message = "every junie MCP entry must carry only fields Junie's schema defines, never a timeout it would ignore.";
      }
      {
        assertion = hasJunieConfigFile "junie/agents/worker.md" && hasJunieConfigFile "junie/agents/reviewer.md";
        message = "every configured subagent profile must reach junie as a Markdown file with frontmatter.";
      }
      {
        # `worker` takes the `edit` role, so its model must be the edit model
        # rather the chat one the session opens on: a module that silently
        # fell back to the session default produces a different string.
        assertion = lib.hasInfix "model: \"edit-model\"" workerAgent;
        message = "the junie worker subagent must take its model from the profile's model_role.";
      }
      {
        assertion = lib.hasInfix "permissionMode: \"acceptEdits\"" workerAgent;
        message = "a workspace-write profile must map to junie's acceptEdits permission mode.";
      }
      {
        assertion = lib.hasInfix "permissionMode: \"plan\"" reviewerAgent;
        message = "a read-only profile must map to junie's plan permission mode.";
      }
      {
        assertion = lib.hasInfix "tools: [\"Read\", \"Glob\", \"Grep\"]" reviewerAgent;
        message = "a read-only profile must restrict junie to its read-only built-in tool groups.";
      }
      {
        assertion = lib.hasInfix "reasoningLevel: \"high\"" workerAgent && lib.hasInfix "reasoningLevel: \"low\"" reviewerAgent;
        message = "each junie subagent must carry its own reasoning effort, not one shared value.";
      }
      {
        assertion = lib.hasInfix "Implement change. Do not switch scope on your own." workerAgent
          && lib.hasInfix "Review diff and report findings. Do not edit files." reviewerAgent;
         message = "each junie subagent body must carry its own instructions.";
      }
    ];
  };
}