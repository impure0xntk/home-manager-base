# jcode writes none of its configuration through a home-manager module, so the
# generated files are the only thing that can be asserted. What is worth pinning
# is the four places jcode diverges from codex, goose and qwen-code:
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
in
{
  config = {
    my.home.ai.harness.enable = true;
    my.home.ai.jcode.enable = true;

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
        assertion = !(parsed ? agents);
        message = "jcode has no per-sub-agent profile format; the generated config must not invent one.";
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
