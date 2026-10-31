# fx keeps its whole configuration under `$HOME/.fx`, so nothing it reads can
# be reached through `xdg.configFile`. What is worth pinning is everything fx
# refuses rather than ignores: `configured_provider.zig` drops the entire
# providers table on one invalid entry, so a bad base_url, a bad connection id
# or an inverted token budget leaves fx with no connection at all. The rest are
# the places fx diverges from codex, jcode and qwen-code:
#
# - MCP servers live in their own `~/.fx/mcp.json` under `mcpServers`, with the
#   command as one argv list rather than a command plus args.
# - A provider with no credential declares `auth.type = "none"` instead of
#   naming a placeholder variable, because fx names only the variable and
#   omits the header when there is none.
# - `provider` and `models` select one connection; every declared provider
#   still gets its own entry under `providers`.
# - fx 0.0.14 registers its hook kinds internally and reads none from a
#   configuration file, so the harness hooks have no route in and the test
#   asserts nothing about them.
{
  config,
  lib,
  ...
}:

let
  harness = config.my.home.ai.harness;

  # Store paths inside generated files come back with string context, which
  # `fromJSON` refuses; the assertions are about content, so context is
  # dropped.
  read = path: builtins.unsafeDiscardStringContext (builtins.readFile path);
  hasFxFile = name: builtins.hasAttr name config.home.file;

  settings = builtins.fromJSON (read config.home.file.".fx/settings.json.orig".source);
  mcp = builtins.fromJSON (read config.home.file.".fx/mcp.json".source);

  local = settings.providers.fx-test-local;
  remote = settings.providers.fx-test-remote;
  # ids must match [A-Za-z][A-Za-z0-9_-]*; anything else has to be scrubbed
  # rather than emitted, or the whole table is dropped.
  dotted = settings.providers.fx-test-dotted;
  reserved = settings.providers.local-gateway;

  serverNames = builtins.attrNames mcp.mcpServers;
in

{
  config = {
    my.home.ai.harness.enable = true;
    my.home.ai.fx.enable = true;

    my.home.ai.providers = [
      {
        name = "fx-test-local";
        url = "http://localhost:4000";
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
          {
            model = "embed-model";
            roles = [ "embed" ];
          }
        ];
      }
      {
        name = "fx-test-remote";
        url = "https://api.example.com";
        api-key-env = "FX_TEST_API_KEY";
        models = [
          {
            model = "remote-chat-model";
            roles = [ "chat" ];
          }
          {
            model = "remote-review-model";
            roles = [ "review" ];
          }
        ];
      }
      {
        name = "fx.test-dotted";
        url = "http://127.0.0.1:4000";
        models = [
          {
            model = "dotted-chat-model";
            roles = [ "chat" ];
          }
        ];
      }
      # `gateway`, `codex` and `grok` are reserved case-insensitively.
      {
        name = "Gateway";
        url = "http://localhost:4001";
        models = [
          {
            model = "reserved-chat-model";
            roles = [ "chat" ];
          }
        ];
      }
    ];

    assertions = [
      {
        # fx derives this directory from `$HOME` alone and exposes no variable
        # to move it, so `home.file` is the only route in.
        assertion = hasFxFile ".fx/settings.json.orig" && hasFxFile ".fx/mcp.json";
        message = "fx's settings and MCP files must be written under the home directory, not XDG config home.";
      }
      {
        # `mcp.json` is a sibling of settings.json, not a table inside it.
        assertion = !builtins.hasAttr "mcpServers" settings;
        message = "fx reads MCP servers from its own mcp.json, never from settings.json.";
      }
      {
        assertion = builtins.hasAttr "mcpServers" mcp;
        message = "fx reads its MCP file under the mcpServers key.";
      }
      {
        assertion = serverNames == builtins.attrNames harness.mcpServers;
        message = "fx must register exactly the harness MCP server registry.";
      }
      {
        # fx takes the command as one argv list, so a `command` string plus a
        # separate `args` array would either drop the arguments or try to run
        # one long word.
        assertion = lib.all (
          server: server.type == "stdio" && builtins.isList server.command && builtins.length server.command > 0
        ) (builtins.attrValues mcp.mcpServers);
        message = "every fx MCP server must be a stdio server whose command is one argv list including its arguments.";
      }
      {
        assertion = local.base_url == "http://localhost:4000/v1";
        message = "fx base_url must carry the /v1 prefix, because fx appends /chat/completions to whatever it is given.";
      }
      {
        assertion = remote.base_url == "https://api.example.com/v1";
        message = "fx base_url must carry the /v1 prefix, because fx appends /chat/completions to whatever it is given.";
      }
      {
        assertion = local.auth == { type = "none"; };
        message = "a fx provider without api-key-env must declare auth type none, so fx omits the header instead of naming an unset variable.";
      }
      {
        assertion = remote.auth == {
          type = "bearer";
          env = "FX_TEST_API_KEY";
        };
        message = "a fx provider with api-key-env must declare bearer auth naming that variable.";
      }
      {
        # fx omits tool choice unless told to send it, and a coding agent that
        # cannot select a tool cannot call one.
        assertion = local.tool_choice_mode == "send" && remote.tool_choice_mode == "send";
        message = "every fx provider must set tool_choice_mode = send, or fx omits tool choice and the model cannot select a tool.";
      }
      {
        # Without a window fx cannot compact before it runs out of context.
        # An embedding model is not selectable in fx, so it gets no entry:
        # `model_metadata` is what `fx models` lists.
        assertion = builtins.attrNames local.model_metadata == [
          "chat-model"
          "edit-model"
        ];
        message = "fx model_metadata must cover every chat-capable model of the provider and none of its embedding models.";
      }
      {
        assertion = local.model_metadata.chat-model.context_window > 0
          && local.model_metadata.chat-model.max_output_tokens < local.model_metadata.chat-model.context_window;
        message = "fx model_metadata must declare a context window larger than max_output_tokens, or fx rejects the whole providers table.";
      }
      {
        # Scrubbing has to happen before emission: one invalid id drops every
        # connection, not only the one carrying it.
        assertion = dotted.base_url == "http://127.0.0.1:4000/v1";
        message = "a provider name fx cannot use as a connection id must still be reachable under a scrubbed id.";
      }
      {
        assertion = reserved.base_url == "http://localhost:4001/v1";
        message = "a provider named after a reserved connection id must still be reachable under a prefixed id.";
      }
      {
        assertion = settings.provider == "fx-test-local";
        message = "fx must open on the connection of the model carrying the chat role.";
      }
      {
        assertion = settings.models.fx-test-local == "chat-model";
        message = "fx's selected model must come from the chat role, not the first declared model.";
      }
      {
        # Every provider gets a connection; `provider`/`models` only pick a
        # default, so the other ones stay selectable with `fx provider <name>`.
        assertion = builtins.length (builtins.attrNames settings.providers) == 4;
        message = "fx must declare one connection per configured provider, not only the selected one.";
      }
      {
        # `reviewer_model` is only valid for a model the same connection
        # serves, and defaults to the selected model otherwise.
        assertion = builtins.hasAttr "reviewer_model" remote;
        message = "fx must name a reviewer model on the connection that also serves the review role.";
      }
      {
        assertion = config.my.home.ai.fx.permissionMode == "auto";
        message = "fx must default to its own auto review rather than asking for every call.";
      }
      {
        assertion = settings.session_titles == false;
        message = "fx must not spend a separate model request on a session title.";
      }
      {
        # fx reads `~/.fx/AGENTS.md` for instructions across projects and
        # `~/.fx/skills` for personal skills, and neither is under XDG.
        assertion = hasFxFile ".fx/AGENTS.md" && hasFxFile ".fx/skills";
        message = "the harness document and skills must reach fx under $HOME/.fx, the only directory fx reads them from.";
      }
    ];
  };
}
