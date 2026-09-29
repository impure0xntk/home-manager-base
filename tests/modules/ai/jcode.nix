# jcode writes none of its configuration through a home-manager module, so the
# generated files are the only thing that can be asserted. What is worth pinning
# is the five places jcode diverges from codex, goose and qwen-code:
#
#   - everything lives in `$XDG_CONFIG_HOME/jcode`, reached through `JCODE_HOME`,
#     not in `$HOME/.jcode`, and the wrapper has to point at the same directory
#     the files are written to.
#   - `[providers.<name>]` profiles are the unit, and a profile without a
#     credential must declare jcode's unauthenticated transport rather than
#     point at a key name that is not set.
#   - MCP servers live in a separate `mcp.json` under `mcpServers`, not in the
#     TOML and not under jcode's historical `servers` key.
#   - hooks are `[hooks]` command strings, so the retrieval deny and the rtk
#     rewrite have to arrive there through their adapters.
#   - the TUI chrome is trimmed through keys this repo adds by patch, so the
#     generated TOML is the only place that decision is observable.
{
  config,
  lib,
  ...
}:

let
  harness = config.my.home.ai.harness;

  # The store paths inside the generated files come back as string context, which
  # `fromTOML` / `fromJSON` refuse; the assertion is about the content, so the
  # context is dropped.
  read = path: builtins.unsafeDiscardStringContext (builtins.readFile path);
  # `?` takes a literal attrpath, not a variable, so the key has to be passed to
  # `builtins.hasAttr`.
  hasJcodeConfigFile = name: builtins.hasAttr name config.xdg.configFile;
  configToml = read config.xdg.configFile."jcode/config.toml".source;
  parsed = builtins.fromTOML configToml;
  parsedMcp = builtins.fromJSON (read config.xdg.configFile."jcode/mcp.json".source);

  # Matched on program names rather than full store paths: the assertion is about
  # the wiring, and a full path would drag its derivation context into the
  # comparison.
  hooks = parsed.hooks or { };
  preToolCommands = hooks.pre_tool or [ ];
  transformCommands = hooks.pre_tool_transform or [ ];
  runsPreToolGate = lib.any (
    command: lib.hasInfix "jcode-pre-tool " command && lib.hasInfix "/retrieval-redirect" command
  ) preToolCommands;
  runsRtkTransform = lib.any (
    command: lib.hasInfix "jcode-pre-tool-transform " command && lib.hasInfix "/rtk" command
  ) transformCommands;

  localProvider = parsed.providers.jcode-test-local;
  remoteProvider = parsed.providers.jcode-test-remote;
  placeholderProvider = parsed.providers.jcode-test-placeholder;
  serverNames = builtins.attrNames parsedMcp.mcpServers;

  # The `[agents]` table and the swarm prompt are the only two places jcode can
  # read a role out of, so both are asserted from their generated content.
  # `worker` takes the `edit` role on purpose: the emitted `swarm_model` is then
  # the edit model rather than the chat one the session opens on, so a module
  # that quietly fell back to the session default produces a different string.
  agents = parsed.agents or { };
  swarmPrompt = read config.xdg.configFile."jcode/swarm-prompt.md".source;

  # `[tools]` is the pair that actually decides the exposed surface, and the
  # pair has to agree: `disable_base_tools` alone drops the MCP tools too, and
  # `enabled` alone still filters MCP. The default pins the module's own
  # inventory rather than narrowing it, so the assertion is a full list, not a
  # membership check. Sorted to match the module's list, since a reordering
  # there would otherwise show up as a diff rather than as a name that dropped.
  #
  # This is jcode 0.89.0's inventory, which is smaller than 0.88.0's: the tools
  # upstream removed are absent rather than named, because an `enabled` entry
  # for a tool the binary does not have is a name that silently does nothing.
  tools = parsed.tools or { };
  baseToolNames = [
    "apply_patch"
    "bash"
    "batch"
    "edit"
    "integration_tools"
    "invalid"
    "jcode_docs"
    "mcp"
    "memory"
    "open"
    "read"
    "replace"
    "swarm"
    "todo"
    "write"
  ];
in
{
  config = {
    my.home.ai.harness.enable = true;
    my.home.ai.jcode.enable = true;

    # jcode has no per-subagent profile file, so a role reaches it as a section
    # of one shared swarm prompt plus the single `[agents]` model/effort pair.
    # `reviewer` is declared alongside `worker` to pin that the pair comes from
    # `worker` alone rather than from whichever role is visited first.
    my.home.ai.jcode.swarm = {
      enable = true;
      spawnMode = "inline";
      stripLayout = "vertical";
      maxConcurrentAgents = 4;
      rootEffort = "xhigh";
      subagents = {
        worker = {
          description = "Scoped implementation work.";
          instructions = "Implement the change. Do not switch scope on your own.";
          model_role = "edit";
          reasoning_effort = "high";
        };
        reviewer = {
          description = "Read-only review.";
          instructions = "Review the diff and report findings. Do not edit files.";
          model_role = "chat";
          reasoning_effort = "low";
        };
      };
    };

    my.home.ai.providers = [
      {
        name = "jcode-test-local";
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
      {
        name = "jcode-test-remote";
        url = "https://api.example.com";
        api-key-env = "JCODE_TEST_API_KEY";
        models = [
          {
            model = "remote-chat-model";
            roles = [ "chat" ];
          }
        ];
      }
      {
        name = "jcode-test-placeholder";
        url = "https://api.example.com";
        # jcode aborts startup on a name its `is_safe_env_key_name` rejects,
        # and a placeholder like this exists only to satisfy qwen, so the
        # module has to drop it rather than forward it.
        api-key-env = "dummy";
        models = [
          {
            model = "placeholder-chat-model";
            roles = [ "chat" ];
          }
        ];
      }
    ];

    assertions = [
      {
        # `JCODE_HOME` is the only thing that moves jcode off `$HOME/.jcode`, so
        # the config home is the only place the files can go.
        assertion = hasJcodeConfigFile "jcode/config.toml" && hasJcodeConfigFile "jcode/mcp.json";
        message = "jcode's config and MCP files must live under the XDG config home.";
      }
      {
        assertion = hasJcodeConfigFile "jcode/prompt-overlay.md";
        message = "the harness document must reach jcode as its global prompt overlay.";
      }
      {
        # `~/.agents/skills` is one of the `$HOME`-relative lookups a `JCODE_HOME`
        # redirect sandboxes under `external/`, so the skills have to be reachable
        # at `$JCODE_HOME/skills` instead.
        assertion = hasJcodeConfigFile "jcode/skills";
        message = "the harness skills must be reachable at JCODE_HOME/skills, the one global skills directory a JCODE_HOME redirect leaves unsandboxed.";
      }
      {
        # jcode appends `/chat/completions` to `base_url`, so the version segment
        # has to be inside it.
        assertion = localProvider.base_url == "http://localhost:1143/v1";
        message = "jcode base_url must carry the /v1 segment, because jcode appends /chat/completions itself.";
      }
      {
        assertion = remoteProvider.base_url == "https://api.example.com/v1";
        message = "jcode base_url must carry the /v1 segment, because jcode appends /chat/completions itself.";
      }
      {
        assertion = localProvider.auth == "none";
        message = "a jcode provider without api-key-env must declare auth = none, or jcode reports it as not configured.";
      }
      {
        assertion = remoteProvider.auth == "bearer";
        message = "a jcode provider with api-key-env must declare auth = bearer.";
      }
      {
        assertion = !localProvider ? api_key_env;
        message = "a jcode provider without api-key-env must not name a key env var it cannot satisfy.";
      }
      {
        assertion = placeholderProvider.auth == "none" && !(placeholderProvider ? api_key_env);
        message = "a jcode provider whose api-key-env is not a readable env var name must declare auth = none, because jcode refuses to start on a name its is_safe_env_key_name rejects.";
      }
      {
        # A profile opens on the model that carries the chat role, not on the
        # first one declared.
        assertion = localProvider.default_model == "chat-model";
        message = "a jcode provider must open on the model declaring the chat role.";
      }
      {
        assertion = lib.map (model: model.id) localProvider.models == [
          "chat-model"
          "edit-model"
        ];
        message = "jcode must expose every model of a provider, not only the chat one.";
      }
      {
        assertion = parsed.provider.default_provider == "jcode-test-local";
        message = "jcode [provider].default_provider must name a configured provider.";
      }
      {
        assertion = parsed.provider.default_model == "chat-model";
        message = "jcode [provider].default_model must come from the chat role.";
      }
      {
        # jcode has no per-subagent profile *file*, but it does have a swarm
        # table, so the assertion is that nothing per-agent appears in it: a
        # `reviewer = { ... }` entry would be a profile format jcode cannot
        # read. What must be there is the flat pair plus the scalar knobs.
        assertion = builtins.attrNames agents == [
          "swarm_effort"
          "swarm_max_concurrent_agents"
          "swarm_model"
          "swarm_root_effort"
          "swarm_spawn_mode"
          "swarm_strip_layout"
        ];
        message = "jcode [agents] must carry only the flat swarm keys jcode reads, never a per-agent profile entry.";
      }
      {
        # `worker` takes the `edit` role, so the model that lands in the single
        # `swarm_model` slot is the `edit` model, not the chat one the session
        # opens on. That difference is what makes the assertion able to fail.
        assertion = agents.swarm_model == "edit-model";
        message = "the jcode swarm model must come from the `worker` role's model_role, not from the chat session default.";
      }
      {
        # The pair is single-valued, so `reviewer`'s low effort must not win
        # the slot. A module that picked the first role it visited would read
        # "low" here.
        assertion = agents.swarm_effort == "high";
        message = "the jcode swarm effort must come from the `worker` role, not from whichever role is visited first.";
      }
      {
        assertion = agents.swarm_spawn_mode == "inline"
          && agents.swarm_strip_layout == "vertical"
          && agents.swarm_max_concurrent_agents == 4
          && agents.swarm_root_effort == "xhigh";
        message = "the jcode swarm scalar knobs must be passed through to [agents] under jcode's own key names.";
      }
      {
        assertion = hasJcodeConfigFile "jcode/swarm-prompt.md";
        message = "jcode must receive the swarm worker prompt at JCODE_HOME/swarm-prompt.md, the one path a JCODE_HOME redirect leaves reachable.";
      }
      {
        # Every configured role has to reach the coordinator, and the role names
        # have to survive as headings, since the name is what a coordinator
        # passes as the `label` of a `swarm spawn` call.
        assertion = lib.all (name: lib.hasInfix "## ${name}" swarmPrompt) [
          "worker"
          "reviewer"
        ];
        message = "every configured jcode swarm role must appear in the swarm prompt as its own section.";
      }
      {
        assertion = lib.hasInfix "Implement the change. Do not switch scope on your own." swarmPrompt
          && lib.hasInfix "Review the diff and report findings. Do not edit files." swarmPrompt;
        message = "the jcode swarm prompt must carry each role's instructions, not only its name.";
      }
      {
        assertion = builtins.hasAttr "mcpServers" parsedMcp && !builtins.hasAttr "servers" parsedMcp;
        message = "jcode reads its MCP file under the mcpServers key.";
      }
      {
        assertion = serverNames == builtins.attrNames harness.mcpServers;
        message = "jcode must register exactly the harness MCP server registry.";
      }
      {
        assertion = lib.all (server: server.command != "" && server.shared && server.timeout_secs > 0) (
          builtins.attrValues parsedMcp.mcpServers
        );
        message = "every jcode MCP server must be a shareable stdio server with a timeout.";
      }
      {
        assertion = runsPreToolGate;
        message = "the jcode pre_tool gate must run the shared retrieval-redirect through its adapter.";
      }
      {
        assertion = runsRtkTransform;
        message = "the jcode pre_tool_transform must run rtk through its adapter.";
      }
      {
        # jcode 0.88.0 has no key for any of these; the patch adds them behind
        # the upstream defaults and this module is what turns them off. A silent
        # rename upstream would turn them back on rather than fail, so the
        # assertion is that the generated TOML says what the module decided.
        assertion = parsed.features.onboarding == false
          && parsed.display.show_header == false
          && parsed.display.show_prompt_numbers == false
          && parsed.display.show_info_widget == false
          && parsed.display.keybinding_hints == false;
        message = "jcode must disable the onboarding wall, the transcript header, the input turn counter, the margin info widget, and the keybinding nudges.";
      }
      {
        # An empty allow-list is the "MCP tools only" switch, so the two keys
        # have to be read together: asserting `enabled` alone would pass for a
        # config that also hides the base tools, and asserting the flag alone
        # would pass for one that exposes nothing at all.
        assertion = tools.disable_base_tools == false && tools.enabled == baseToolNames;
        message = "jcode [tools] must expose the full base tool inventory by default, with disable_base_tools off so MCP tools survive the allow-list.";
      }
      {
        # refresh-index is the SessionStart counterpart, and it is skipped outside
        # an indexed tree, so the command list rather than a side effect.
        assertion = lib.any (command: lib.hasInfix ".codegraph" command) (hooks.session_start or [ ]);
        message = "the jcode session_start hook must refresh the codegraph index where it already governs the tree.";
      }
      {
        assertion = lib.any (command: lib.hasInfix ".zvec-grep" command) (hooks.session_start or [ ]);
        message = "the jcode session_start hook must refresh the zvec-grep index where it already governs the tree.";
      }
    ];
  };
}
