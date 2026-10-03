{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.home.ai;

  # Fence matches `network.allowedDomains` by host name, so a provider URL only
  # becomes an allow rule once reduced to host and port. The scheme supplies the
  # default port, because a loopback provider reached on its implicit port still
  # needs its own bridge on Linux.
  parseProviderUrl =
    url:
    let
      separated = lib.my.separateHostAndPort url;
      scheme = lib.head (lib.splitString "://" url);
    in
    {
      host = lib.removePrefix "${scheme}://" separated.schemaAndHost;
      port = if separated.port != "" then lib.toInt separated.port else if scheme == "https" then 443 else if scheme == "http" then 80 else null;
    };

  providerEndpoints = map (provider: parseProviderUrl provider.url) (cfg.providers or [ ]);

  # A loopback endpoint is not a domain Fence can allow-list: loopback traffic is
  # gated by `allowLocalOutbound` instead, and on Linux every host port needs its
  # own bridge through `allowLocalOutboundPorts`. A provider marked `isLocal`
  # while reached through a real hostname stays in `allowedDomains`, because the
  # domain filter is what Fence can express for it.
  isLoopbackHost =
    host:
    # `separateHostAndPort` keeps an IPv6 literal bracketed, because that is the
    # form Fence and the proxy match on, so the loopback literal is bracketed too.
    lib.elem host [
      "localhost"
      "[::1]"
      "::1"
    ] || lib.hasPrefix "127." host;

  remoteHosts = lib.unique (lib.filter (host: !(isLoopbackHost host)) (map (endpoint: endpoint.host) providerEndpoints));

  localPorts =
    let
      ports = map (endpoint: endpoint.port) (builtins.filter (endpoint: isLoopbackHost endpoint.host) providerEndpoints);
    in
    lib.unique (lib.filter (port: port != null) ports);

  # A provider URL with neither an explicit port nor a scheme to default it
  # from leaves nothing for the loopback bridge to forward, so the agent could
  # never reach it.
  localProvidersWithoutPort = map (
    provider: provider.name
  ) (
    builtins.filter (
      provider:
      let
        endpoint = parseProviderUrl provider.url;
      in
      isLoopbackHost endpoint.host && endpoint.port == null
    ) (cfg.providers or [ ])
  );

  # Every profile reaches the AI backends the harness itself is configured with,
  # so the allow rules are derived from `my.home.ai.providers` rather than listed
  # per profile. Fence denies outbound traffic matching no rule, so a machine with
  # no provider gets no network block at all and stays as unrestricted as before.
  # `network` is assembled as one nested attrset because `//` merges shallowly
  # and would otherwise drop the sibling keys.
  settingsForProviders =
    if remoteHosts == [ ] && localPorts == [ ] then
      { }
    else
      {
        network = {
          allowedDomains = remoteHosts;
        }
        // lib.optionalAttrs (localPorts != [ ]) {
          allowLocalOutbound = true;
          allowLocalOutboundPorts = localPorts;
        };
      };

  defaultProfiles = {
    default = {
      default = true;
      settings = {
        filesystem = {
          allowWrite = ["." "/tmp"];
        };
      };
    };
  };

  # Fence masks a whole executable path for a runtime deny, so denying one
  # coreutils command such as `chroot` would also block `cat`, `head` and every
  # other alias sharing the same binary. Accepting every coreutils command
  # keeps the deny rule preflight-only instead of masking the shared binary.
  # Both variants ship because PATH inside the sandbox may pick either one.
  coreutilsCommands = lib.unique (
    lib.concatMap
      (pkg: builtins.attrNames (builtins.readDir "${pkg}/bin"))
      [ pkgs.coreutils-full ]
  );

  # Baseline every profile gets: the Nix-provided binaries must stay readable
  # and runnable inside the sandbox, and the AI providers the harness is
  # configured with must stay reachable.
  settingsForNixEnv = {
    "$schema" = "https://raw.githubusercontent.com/fencesandbox/fence/main/docs/schema/fence.schema.json";
    filesystem = {
      allowRead = ["/nix/store"];
      allowExecute = ["/nix/store"];
    };
    command.acceptSharedBinaryCannotRuntimeDeny = coreutilsCommands;
  }
  // settingsForProviders;

  finalProfiles = lib.mapAttrs' (name: entry: {
    inherit name;
    value = lib.my.deepMerge entry { settings = settingsForNixEnv; };
  }) cfg.harness.sandbox.profiles;

  defaultProfileNames = lib.attrNames (lib.filterAttrs (_name: entry: entry.default) finalProfiles);
in
{
  options.my.home.ai.harness.sandbox = with lib; with lib.types; {
    enable = mkEnableOption "Whether to enable the AI harness sandbox";
    profiles = mkOption {
      type = attrsOf (submodule {
        options = {
          settings = mkOption {
            type = attrs;
            description = ''
              Settings for the sandbox profile, merged with the settings every
              profile needs (schema URL, /nix/store access, and network access to
              the providers in `my.home.ai.providers`). Rendered as JSON for
              Fence, see
              https://github.com/fencesandbox/fence/blob/main/docs/configuration.md
            '';
          };
          default = mkEnableOption ''
            Whether to use this profile as the default profile of the AI
            harness sandbox. Its settings become `fence/fence.json`, the config
            Fence loads when it finds no project-local config. At most one
            profile may set this.
          '';
        };
      });
      default = defaultProfiles;
      description = ''
        Fence sandbox profiles. Each profile is written to
        `fence/<name>.json`, and the single profile with `default = true` is
        copied to `fence/fence.json`, the config Fence loads when it finds no
        project-local config. Without one, `fence/fence.json` is not written.
      '';
    };
  };
  config = lib.mkIf (cfg.harness.enable && cfg.harness.sandbox.enable) {
    home.packages = with pkgs; [
      fence
    ];

    xdg.configFile = lib.mkMerge [
      (lib.mapAttrs' (name: entry: {
        name = "fence/${name}.json";
        value.text = builtins.toJSON entry.settings + "\n";
      }) finalProfiles)
      (lib.optionalAttrs (defaultProfileNames != [ ]) {
        "fence/fence.json".text = builtins.toJSON finalProfiles.${lib.head defaultProfileNames}.settings + "\n";
      })
    ];

    assertions = [
      {
        assertion = builtins.length defaultProfileNames <= 1;
        message = "my.home.ai.harness.sandbox.profiles: at most one profile may set default = true, but found: ${lib.concatStringsSep ", " defaultProfileNames}";
      }
      {
        assertion = localProvidersWithoutPort == [ ];
        message = "my.home.ai.providers: a loopback provider URL needs an explicit port, or a scheme to default the port from, for Fence to bridge it: ${lib.concatStringsSep ", " localProvidersWithoutPort}";
      }
    ];
  };
}
