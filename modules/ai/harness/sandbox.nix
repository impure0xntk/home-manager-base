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
      schemeParts = lib.splitString "://" url;
      hasScheme = builtins.length schemeParts > 1;
      scheme = if hasScheme then lib.head schemeParts else "";
      withoutScheme = lib.concatStringsSep "://" (if hasScheme then lib.tail schemeParts else [ url ]);
      # The authority ends at the first path, query or fragment separator, and
      # any `user:password@` in front of it is not part of the host.
      authority = lib.removePrefix "${lib.concatStringsSep "@" (lib.init (lib.splitString "@" withoutScheme))}@" (
        lib.head (lib.splitString "/" (lib.head (lib.splitString "?" (lib.head (lib.splitString "#" withoutScheme)))))
      );
      # An IPv6 literal is bracketed in a URL, and the bracket is what separates
      # the host from the port there, not a colon.
      isBracketed = lib.hasPrefix "[" authority;
      segments = lib.splitString (if isBracketed then "]" else ":") authority;
      portText =
        if isBracketed then
          lib.removePrefix ":" (lib.last segments)
        else if builtins.length segments > 1 then
          lib.last segments
        else
          "";
      # Only a numeric tail is a port, so a bare `host:anything` authority does
      # not turn its tail into one.
      port = if portText != "" && lib.match "[0-9]+" portText != null then lib.toInt portText else null;
    in
    {
      host = lib.toLower (lib.removePrefix "[" (lib.head segments));
      port = if port != null then port else if scheme == "https" then 443 else if scheme == "http" then 80 else null;
    };

  providerEndpoints = map (provider: parseProviderUrl provider.url) (cfg.providers or [ ]);

  # A loopback endpoint is not a domain Fence can allow-list: loopback traffic is
  # gated by `allowLocalOutbound` instead, and on Linux every host port needs its
  # own bridge through `allowLocalOutboundPorts`. A provider marked `isLocal`
  # while reached through a real hostname stays in `allowedDomains`, because the
  # domain filter is what Fence can express for it.
  isLoopbackHost =
    host: lib.elem host [
      "localhost"
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
  # per profile. Fence denies outbound traffic matching no rule, and an empty
  # `allowedDomains` is itself a deny-all, so the whole block is omitted unless a
  # provider needs it and a profile without providers stays as restrictive as
  # before.
  settingsForProviders =
    {
      network.allowedDomains = remoteHosts;
    }
    // lib.optionalAttrs (localPorts != [ ]) {
      network.allowLocalOutbound = true;
      network.allowLocalOutboundPorts = localPorts;
    }
    // lib.optionalAttrs (remoteHosts == [ ] && localPorts == [ ]) { };

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
