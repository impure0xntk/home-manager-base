# The fence sandbox denies every outbound connection that matches no network
# rule, so the endpoints the harness is configured with are exactly what the
# agent cannot reach unless the module derives the rules from those lists. A
# harness session dials more than the AI backends: every agent here also talks to
# the MCP hub servers, and deriving from those too is what keeps a remote hub
# reachable. The generated JSON is the only place the derivation is observable,
# so the assertions pin the parsed content rather than the Nix attributes:
#
#   - a remote provider or hub host lands in `network.allowedDomains`, reduced to
#     a bare host name, because that is the form fence matches on.
#   - a loopback provider cannot be expressed as a domain at all. It is bridged
#     through `allowLocalOutbound` / `allowLocalOutboundPorts` instead, and the
#     port has to come out of the URL rather than out of `isLocal`.
#   - both keys have to survive together. `//` merges shallowly, so composing the
#     two as separate dotted keys silently drops one of them and produces a
#     config that reads as valid while the agent loses its remote provider.
#
# The filesystem rules are asserted the same way. An agent keeps its sessions,
# caches and tool history outside the working directory, and a profile that only
# allows the workspace leaves those on a read-only bind, so the agent fails to
# start with EROFS on its first write. The state roots are derived from the
# options that point the agent or tool at them, so enabling one is what adds its
# directory, and the assertion is recomputed from the evaluated configuration
# rather than hardcoded.
#
# The `fence-<profile>` aliases are asserted the same way: the alias is the only
# thing that makes a profile launchable without typing a store-dependent path, so
# the assertion checks that the alias set is exactly one `fence-` prefixed name
# per profile and that each value names the profile's own rendered file under
# `xdg.configHome` rather than some other path.
{
  config,
  lib,
  ...
}:

let
  fenceConfigFile = "fence/default.json";

  # The store paths inside the generated file come back as string context, which
  # `fromJSON` refuses; the assertion is about the content, so the context is
  # dropped.
  read = path: builtins.unsafeDiscardStringContext (builtins.readFile path);

  parsed = builtins.fromJSON (read config.xdg.configFile.${fenceConfigFile}.source);
  network = parsed.network or { };
  allowWrite = parsed.filesystem.allowWrite or [ ];

  # `providers` is a `listOf (submodule ...)`, and such lists concatenate rather
  # than replace, so another module in this evaluation can contribute its own
  # providers. The expectation is therefore recomputed from the evaluated list
  # instead of hardcoded, which keeps the assertions about the derivation itself
  # rather than about how many providers happen to be configured.
  hostOf =
    url:
    let
      separated = lib.my.separateHostAndPort url;
      scheme = lib.head (lib.splitString "://" url);
    in
    lib.removePrefix "${scheme}://" separated.schemaAndHost;

  isLoopback = host: lib.elem host [ "localhost" "[::1]" "::1" ] || lib.hasPrefix "127." host;

  hostsOfProviders = map (provider: hostOf provider.url) config.my.home.ai.providers;

  # The MCP hub servers carry host and port as separate options, so there is no
  # URL to reduce and no loopback scheme to strip.
  hostsOfHubServers = map (server: server.host) config.my.home.mcp.hub.client.servers;

  configuredHosts = lib.unique (
    lib.filter (host: !(isLoopback host)) (hostsOfProviders ++ hostsOfHubServers)
  );

  # Set below to decide which shape the generated config has to have.
  expectLocalPort = 11434;

  # The enabled agents and harness tools are what decide which state roots the
  # profile has to allow writing, so the expectation is derived from the same
  # options the module reads rather than restated as a literal list.
  cfg = config.my.home.ai;

  expectStateRoots =
    lib.unique (
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
  # adds are absolute paths: a literal `~` resolves against the sandbox home
  # rather than the user's, and a bare relative name resolves against the working
  # directory, so either form silently allows nothing. The profile's own entries
  # are exempt because `.` is how a profile names the working directory.
  stateRootsAbsolute = builtins.all (path: lib.hasPrefix "/" path) expectStateRoots;

  sandboxProfiles = config.my.home.ai.harness.sandbox.profiles;

  profileNames = lib.attrNames sandboxProfiles;

  # One alias per profile, generated from the evaluated profile names so the
  # assertion does not care how many profiles the machine configures.
  expectedAliasNames = map (name: "fence-${name}") profileNames;

  expectedAliases = lib.listToAttrs (map (
    name: {
      name = "fence-${name}";
      value = "fence --settings ${config.xdg.configHome}/fence/${name}.json";
    }
  ) profileNames);

  # The shell module sets the same attrset on fish, so an alias that exists for
  # bash but not fish is only half deployed.
  fenceAliases =
    lib.filterAttrs (name: _: lib.hasPrefix "fence-" name) config.programs.bash.shellAliases;
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
        # A path and an uppercase host, neither of which may leak into the allow
        # rule: fence matches bare host names.
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
        # A local provider is reached over loopback, which no allow rule can
        # express, so only the port is recoverable from this URL.
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
        assertion = builtins.hasAttr fenceConfigFile config.xdg.configFile;
        message = "the fence sandbox profile must reach the XDG config home, which is where fence looks for it.";
      }
      {
        assertion = lib.sort (a: b: a < b) (network.allowedDomains or [ ]) == lib.sort (a: b: a < b) configuredHosts;
        message = "network.allowedDomains must be exactly the hosts of the non-loopback providers and MCP hub servers, with nothing extra, nothing missing and no duplicates.";
      }
      {
        # The MCP hub server is not an AI provider, so deriving the rules from
        # the providers alone leaves it denied.
        assertion = lib.elem "hub.example.net" (network.allowedDomains or [ ]);
        message = "a remote MCP hub server must land in network.allowedDomains; the agent reaches the hub through the same network rules as the providers, and a host with no rule is denied with a 403 before the request is made.";
      }
      {
        # The port, path, scheme and case of the URL are not part of a fence
        # allow rule, and a leftover of any of them makes the rule match nothing.
        assertion = !(lib.any (
          entry: builtins.match ".*[/:].*" entry != null
        ) (network.allowedDomains or [ ]));
        message = "network.allowedDomains entries must be bare host names, since fence matches domains and nothing else.";
      }
      {
        # A loopback provider is bridged by port, so the port has to reach the
        # allow rules. The membership is pinned rather than a count because
        # `providers` concatenates across modules and another test module can
        # contribute its own loopback provider here.
        assertion = lib.elem expectLocalPort (network.allowLocalOutboundPorts or [ ]);
        message = "a loopback provider must be bridged through allowLocalOutboundPorts, since Linux forwards loopback ports one by one.";
      }
      {
        # The composition bug this guards against: composing the two as separate
        # dotted keys and merging them shallowly keeps only the last one, and the
        # result is still a valid config that happens to allow nothing useful.
        assertion = builtins.hasAttr "allowedDomains" network && builtins.hasAttr "allowLocalOutboundPorts" network;
        message = "network.allowedDomains and network.allowLocalOutboundPorts must survive the same merge; a shallow one drops one of them and leaves the agent unable to reach any provider.";
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
        message = "every state root of an enabled agent or harness tool must be writable; the agent keeps its sessions, caches and tool history there, and a read-only bind there makes it fail to start with EROFS.";
      }
      {
        assertion = stateRootsAbsolute;
        message = "the state roots the module adds to filesystem.allowWrite must be absolute; a literal ~ resolves against the sandbox home and a bare relative name against the working directory, so either allows nothing useful.";
      }
      {
        assertion = !(lib.elem "~" allowWrite) && !(lib.elem "~/.config/jcode" allowWrite);
        message = "filesystem.allowWrite must not carry a literal ~; fence resolves it against its own sandbox home rather than the user's, so the agent state stays read-only.";
      }
      {
        assertion = lib.sort (a: b: a < b) (lib.attrNames fenceAliases) == lib.sort (a: b: a < b) expectedAliasNames;
        message = "there must be exactly one fence-<profile> alias per configured sandbox profile; a missing alias leaves the profile unreachable and a stale one points at a profile that no longer exists.";
      }
      {
        assertion = lib.attrByPath [ "fence-default" ] null fenceAliases == expectedAliases."fence-default";
        message = "the fence-<profile> alias must run fence against the profile's own rendered settings file under xdg.configHome, not against a name, a different profile, or a path fence cannot read.";
      }
      {
        assertion = lib.attrByPath [ "fence-default" ] null config.programs.fish.shellAbbrs == expectedAliases."fence-default";
        message = "the fence-<profile> alias must reach fish as well as bash, otherwise the primary shell on this system cannot start a sandbox profile.";
      }
    ];
  };
}
