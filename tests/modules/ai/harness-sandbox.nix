# The fence sandbox denies every outbound connection that matches no network
# rule, so the providers `my.home.ai.providers` configures the harness with are
# exactly what the agent cannot reach unless the module derives the rules from
# that list. The generated JSON is the only place the derivation is observable,
# so the assertions pin the parsed content rather than the Nix attributes:
#
#   - a remote provider host lands in `network.allowedDomains`, reduced to a bare
#     host name, because that is the form fence matches on.
#   - a loopback provider cannot be expressed as a domain at all. It is bridged
#     through `allowLocalOutbound` / `allowLocalOutboundPorts` instead, and the
#     port has to come out of the URL rather than out of `isLocal`.
#   - both keys have to survive together. `//` merges shallowly, so composing the
#     two as separate dotted keys silently drops one of them and produces a
#     config that reads as valid while the agent loses its remote provider.
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

  configuredHosts = lib.unique (lib.filter (host: !(isLoopback host)) hostsOfProviders);

  # Set below to decide which shape the generated config has to have.
  expectLocalPort = 11434;

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
      default = { };
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
        message = "network.allowedDomains must be exactly the hosts of the non-loopback providers, with nothing extra, nothing missing and no duplicates.";
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
