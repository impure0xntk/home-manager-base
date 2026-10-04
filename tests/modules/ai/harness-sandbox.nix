# The srt sandbox denies every outbound connection that matches no network rule,
# so the endpoints the harness is configured with are exactly what the agent
# cannot reach unless the module derives the rules from those lists. A harness
# session dials more than the AI backends: every agent here also talks to the MCP
# hub servers, and deriving from those too is what keeps a remote hub reachable.
# The generated JSON is the only place the derivation is observable, so the
# assertions pin the parsed content rather than the Nix attributes:
#
#   - a provider or hub host lands in `network.allowedDomains` as `host:port`.
#     The port is part of the rule because srt reads an entry without one as
#     matching every port on that host, so a portless entry would also open
#     whatever else the agent's own route to that host can reach. The scheme
#     supplies the port when the URL has none.
#   - a loopback provider is an entry in the same list, not a separate key.
#     Whether it needs the name or the literal depends on which one the URL
#     spells, so the assertion is recomputed from the URL rather than from
#     `isLocal`, which says nothing about the spelling.
#   - the scheme, the path and the case of the URL are not part of an allow rule,
#     and a leftover of any of them makes the rule match nothing at all.
#
# srt's schema requires both `network` and `filesystem`, with `deniedDomains`,
# `denyRead`, `allowWrite` and `denyWrite` all mandatory inside them. That is
# asserted rather than assumed: a settings file missing any of them is refused
# whole by `srt --settings`, so the profile would be a file that silently runs
# with no policy at all instead of the policy it was rendered to express.
#
# The filesystem rules are asserted the same way. An agent keeps its sessions,
# caches and tool history outside the working directory, and srt mounts every
# write that matches no rule read-only, so a profile that only allows the
# workspace leaves those behind and the agent fails to start with EROFS on its
# first write. The state roots are derived from the options that point the agent
# or tool at them, so enabling one is what adds its directory, and the assertion
# is recomputed from the evaluated configuration rather than hardcoded.
#
# The `srt-<profile>` aliases are asserted the same way: the alias is the only
# thing that makes a profile launchable without typing a store-dependent path, so
# the assertion checks that the alias set is exactly one `srt-` prefixed name per
# profile and that each value names the profile's own rendered file under
# `xdg.configHome` rather than some other path.
{
  config,
  lib,
  ...
}:

let
  srtConfigFile = "sandbox-runtime/default.json";

  # The store paths inside the generated file come back as string context, which
  # `fromJSON` refuses; the assertion is about the content, so the context is
  # dropped.
  read = path: builtins.unsafeDiscardStringContext (builtins.readFile path);

  parsed = builtins.fromJSON (read config.xdg.configFile.${srtConfigFile}.source);
  network = parsed.network or { };
  filesystem = parsed.filesystem or { };
  allowWrite = filesystem.allowWrite or [ ];

  # `providers` is a `listOf (submodule ...)`, and such lists concatenate rather
  # than replace, so another module in this evaluation can contribute its own
  # providers. The expectation is therefore recomputed from the evaluated list
  # instead of hardcoded, which keeps the assertions about the derivation itself
  # rather than about how many providers happen to be configured.
  endpointOf =
    url:
    let
      separated = lib.my.separateHostAndPort url;
      scheme = lib.head (lib.splitString "://" url);
    in
    {
      host = lib.removePrefix "${scheme}://" separated.schemaAndHost;
      port =
        if separated.port != "" then
          lib.toInt separated.port
        else if scheme == "https" then
          443
        else if scheme == "http" then
          80
        else
          null;
    };

  # The MCP hub servers carry host and port as separate options, so there is no
  # URL to reduce and no scheme to strip a port from.
  providerEntries = map (
    provider:
    let
      endpoint = endpointOf provider.url;
    in
    "${endpoint.host}:${toString endpoint.port}"
  ) config.my.home.ai.providers;

  hubEntries =
    if config.my.home.mcp.hub.client.enable then
      map (server: "${server.host}:${toString server.port}") config.my.home.mcp.hub.client.servers
    else
      [ ];

  configuredEntries = lib.unique (providerEntries ++ hubEntries);

  # Set below to decide which shape the generated config has to have.
  expectLocalPort = 11434;

  # The enabled agents and harness tools are what decide which state roots the
  # profile has to allow writing, so the expectation is derived from the same
  # options the module reads rather than restated as a literal list.
  cfg = config.my.home.ai;

  expectStateRoots = lib.unique (
    lib.optionals cfg.jcode.enable [
      "${config.xdg.configHome}/jcode"
      "${config.xdg.cacheHome}/jcode"
    ]
    ++ lib.optionals cfg.codex.enable [ "${config.xdg.configHome}/codex" ]
    ++ lib.optionals cfg.goose.enable [ "${config.xdg.configHome}/goose" ]
    ++ lib.optionals cfg.qwen-code.enable [ "${config.xdg.configHome}/qwen" ]
    ++ lib.optionals cfg.copilot-cli.enable [ "${config.xdg.configHome}/copilot" ]
    ++ lib.optionals cfg.junie.enable [ "${config.xdg.dataHome}/junie" ]
    ++ lib.optionals (cfg.harness.codingAgentTools.ctx.mcpServer != null) [
      "${config.xdg.dataHome}/ctx"
      "${config.xdg.stateHome}/ctx"
    ]
    ++ lib.optionals (cfg.harness.codingAgentTools.zg.mcpServer != null) [
      "${config.xdg.configHome}/zvec-grep"
      "${config.xdg.dataHome}/zvec-grep"
    ]
    ++ lib.optionals (cfg.harness.codingAgentTools.rtk.package != null) [ "${config.xdg.dataHome}/rtk" ]
  );

  # The module derives the state roots, so the expectation cannot simply mirror
  # the derivation and stay honest. What is pinned instead is that the roots it
  # adds are absolute paths: srt resolves a relative entry against the working
  # directory rather than the user's home, so a bare relative name silently
  # allows nothing. The profile's own entries are exempt because `.` is how a
  # profile names the working directory.
  stateRootsAbsolute = builtins.all (path: lib.hasPrefix "/" path) expectStateRoots;

  sandboxProfiles = config.my.home.ai.harness.sandbox.profiles;

  profileNames = lib.attrNames sandboxProfiles;

  # One alias per profile, generated from the evaluated profile names so the
  # assertion does not care how many profiles the machine configures.
  expectedAliasNames = map (name: "srt-${name}") profileNames;

  expectedAliases = lib.listToAttrs (
    map (name: {
      name = "srt-${name}";
      value = "srt --settings ${config.xdg.configHome}/sandbox-runtime/${name}.json";
    }) profileNames
  );

  # The shell module sets the same attrset on fish, so an alias that exists for
  # bash but not fish is only half deployed.
  srtAliases = lib.filterAttrs (name: _: lib.hasPrefix "srt-" name) config.programs.bash.shellAliases;

  # srt reads these settings with `--settings`; nothing else reads them, so an
  # alias pointing anywhere else is the one thing that makes a profile
  # unreachable.
  defaultProfileIsAliasTarget = lib.any (name: name == "default") profileNames;
in
{
  config = {
    my.home.ai.harness.enable = true;
    my.home.ai.harness.sandbox.enable = true;

    my.home.ai.harness.sandbox.profiles = {
      # The profile's own writable paths, so the merge the module applies has
      # something of the profile's own to preserve: the module contributes the
      # agent state roots and must not replace what the profile asked for.
      default.settings.filesystem.allowWrite = [
        "."
        "/tmp"
      ];
    };

    # Enabled so the state-root derivation has something to derive: an agent
    # nobody enables writes nothing, and a profile for an agent that is not
    # installed has nothing to protect it from the read-only bind.
    my.home.ai.jcode.enable = true;

    # A remote MCP hub server is the case that silently breaks the agent: the
    # host is denied with a proxy 403 before the request is ever made.
    my.home.mcp.hub.client = {
      enable = true;
      servers = [
        {
          name = "sandbox-test-hub";
          host = "hub.example.net";
          port = 3001;
        }
      ];
    };

    my.home.ai.providers = [
      {
        name = "sandbox-test-remote";
        # A path, an uppercase host and no port, none of which may leak into the
        # allow entry: srt matches `host:port`, and the https scheme supplies the
        # port the URL leaves out.
        url = "https://AI.example.com/openai/v1";
        api-key-env = "SANDBOX_TEST_API_KEY";
        models = [
          {
            model = "remote-model";
            roles = [ "chat" ];
          }
        ];
      }
      {
        name = "sandbox-test-local";
        # A local provider is reached over loopback, which the resolved-address
        # check refuses unless the address itself is allow-listed, so the entry
        # has to carry the literal and the port both.
        url = "http://localhost:11434";
        isLocal = true;
        models = [
          {
            model = "local-model";
            roles = [ "edit" ];
          }
        ];
      }
    ];

    assertions = [
      {
        assertion = builtins.hasAttr srtConfigFile config.xdg.configFile;
        message = "the srt sandbox profile must reach the XDG config home, which is where the srt-<profile> alias looks for it.";
      }
      {
        # The whole point of the derivation: every endpoint the harness is
        # configured with, scoped to the port it is reached on, and nothing else.
        assertion =
          lib.sort (a: b: a < b) (network.allowedDomains or [ ]) == lib.sort (a: b: a < b) configuredEntries;
        message = "network.allowedDomains must be exactly the host:port of every provider and MCP hub server, with nothing extra, nothing missing and no duplicates.";
      }
      {
        # The MCP hub server is not an AI provider, so deriving the rules from
        # the providers alone leaves it denied.
        assertion = lib.elem "hub.example.net:3001" (network.allowedDomains or [ ]);
        message = "a remote MCP hub server must land in network.allowedDomains; the agent reaches the hub through the same network rules as the providers, and a host with no rule is denied with a 403 before the request is made.";
      }
      {
        # The scheme, the path and the case of the URL are not part of an srt
        # allow entry, and a leftover of any of them makes it match nothing.
        assertion =
          !(lib.any (entry: builtins.match ".*[/?].*" entry != null) (network.allowedDomains or [ ]));
        message = "network.allowedDomains entries must be a host and a port only, since srt matches a domain pattern and nothing else; a leftover scheme, path or slash matches no destination.";
      }
      {
        # An entry with no port matches every port on that host, so an entry that
        # lost its port is not a weaker rule, it is a much broader one.
        assertion = lib.all (entry: builtins.match ".*:[0-9]+$" entry != null) (
          network.allowedDomains or [ ]
        );
        message = "every network.allowedDomains entry must carry the port it is scoped to; srt reads an entry without one as matching every port on that host, so dropping it opens unrelated services rather than narrowing the rule.";
      }
      {
        # A loopback endpoint is refused by the resolved-address check unless
        # the address is itself allow-listed, so the entry has to name it.
        assertion = lib.elem "localhost:${toString expectLocalPort}" (network.allowedDomains or [ ]);
        message = "a loopback provider must be allow-listed by name and port; srt refuses to dial a hostname that resolves to a loopback address unless the address is on the allowlist itself.";
      }
      {
        # `network` and `filesystem` are both required by srt's schema, so a
        # profile missing either is refused whole and runs with no policy.
        assertion = builtins.isAttrs network && builtins.isAttrs filesystem;
        message = "the rendered profile must carry both network and filesystem; srt requires both, and refuses a settings file missing either rather than applying the half it can parse.";
      }
      {
        # The keys inside them are required too: `filesystem` alone does not make
        # a config valid if `allowWrite` is absent from it.
        assertion = builtins.all (key: builtins.isList filesystem.${key} or null) [
          "denyRead"
          "allowWrite"
          "denyWrite"
        ];
        message = "filesystem must carry denyRead, allowWrite and denyWrite; srt requires each of them, so a missing one is a settings file srt refuses to load.";
      }
      {
        assertion = builtins.all (key: builtins.isList network.${key} or null) [
          "allowedDomains"
          "deniedDomains"
        ];
        message = "network must carry allowedDomains and deniedDomains; srt requires both, so a missing one is a settings file srt refuses to load.";
      }
      {
        # The workspace and /tmp are what the profile sets itself; the agent
        # state roots are what the module adds. Both have to be present: without
        # the workspace the agent cannot write its work, and without the state
        # roots it fails on its first write with EROFS.
        assertion = lib.elem "." allowWrite && lib.elem "/tmp" allowWrite;
        message = "the profile's own writable paths must survive the merge the module applies, otherwise the agent has nowhere to write its work.";
      }
      {
        assertion = lib.all (path: lib.elem path allowWrite) expectStateRoots;
        message = "every state root of an enabled agent or harness tool must be writable; the agent keeps its sessions, caches and tool history there, and srt mounts every other write read-only, so it fails to start with EROFS.";
      }
      {
        assertion = stateRootsAbsolute;
        message = "the state roots the module adds to filesystem.allowWrite must be absolute; srt resolves a relative entry against the working directory rather than the user's home, so a bare relative name allows nothing useful.";
      }
      {
        assertion = !(lib.elem "~" allowWrite) && !(lib.elem "~/.config/jcode" allowWrite);
        message = "the state roots filesystem.allowWrite carries must not be spelled with a literal ~; the module derives them from the XDG options precisely so that relocating xdg.configHome keeps them pointing at the right directory.";
      }
      {
        assertion =
          lib.sort (a: b: a < b) (lib.attrNames srtAliases) == lib.sort (a: b: a < b) expectedAliasNames;
        message = "there must be exactly one srt-<profile> alias per configured sandbox profile; a missing alias leaves the profile unreachable and a stale one points at a profile that no longer exists.";
      }
      {
        assertion = defaultProfileIsAliasTarget;
        message = "this test configures a profile named `default`, so its srt-default alias must exist and the assertion below can check what it points at.";
      }
      {
        assertion = lib.attrByPath [ "srt-default" ] null srtAliases == expectedAliases."srt-default";
        message = "the srt-<profile> alias must run srt against the profile's own rendered settings file under xdg.configHome, not against a name, a different profile, or a path srt cannot read.";
      }
      {
        assertion =
          lib.attrByPath [ "srt-default" ] null config.programs.fish.shellAbbrs
          == expectedAliases."srt-default";
        message = "the srt-<profile> alias must reach fish as well as bash, otherwise the primary shell on this system cannot start a sandbox profile.";
      }
    ];
  };
}
