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

  # The AI providers are not the only endpoints a harness session talks to:
  # every agent here also dials the MCP hub servers in `my.home.mcp.hub.client`,
  # and a host fence has no rule for is denied with a proxy 403 before the
  # request is ever made. Deriving the rules from that list too keeps the
  # sandbox in step with the servers the machine actually configures, instead
  # of repeating a hostname that a profile edit can drift away from.
  #
  # `servers` has a default, so the option has a value before a machine
  # configures any, and that default is a loopback address on port 3001. A
  # disabled client is what keeps it from being an endpoint: nothing generates a
  # wrapper for it and nothing connects, so bridging the port on a machine that
  # never enabled the client would forward a real host port for no reason. The
  # gate is on `enable` rather than on the default's value, because that value
  # is a legitimate loopback host a machine can genuinely configure.
  mcpHubEndpoints =
    if config.my.home.mcp.hub.client.enable then
      map (
        server: {
          inherit (server) host port;
        }
      ) config.my.home.mcp.hub.client.servers
    else
      [ ];

  mcpHubHosts = lib.unique (lib.filter (host: !(isLoopbackHost host)) (map (endpoint: endpoint.host) mcpHubEndpoints));

  mcpHubPorts = lib.unique (map (endpoint: endpoint.port) (builtins.filter (endpoint: isLoopbackHost endpoint.host) mcpHubEndpoints));

  # Every profile reaches the AI backends and the MCP hub servers the harness
  # itself is configured with, so the allow rules are derived from
  # `my.home.ai.providers` and `my.home.mcp.hub.client.servers` rather than
  # listed per profile. Fence denies outbound traffic matching no rule, so a
  # machine with no provider gets no network block at all and stays as
  # unrestricted as before.
  # `network` is assembled as one nested attrset because `//` merges shallowly
  # and would otherwise drop the sibling keys.
  settingsForNetwork =
    let
      remote = lib.unique (remoteHosts ++ mcpHubHosts);
      local = lib.unique (localPorts ++ mcpHubPorts);
    in
    if remote == [ ] && local == [ ] then
      { }
    else
      {
        network = {
          allowedDomains = remote;
        }
        // lib.optionalAttrs (local != [ ]) {
          allowLocalOutbound = true;
          allowLocalOutboundPorts = local;
        };
      };

  # fence does NOT support multi extends, so concat via nix
  templates =
    let
      # jsonc to json
      toPureJsonFile = name: file: pkgs.runCommand "${name}-clean-json" { nativeBuildInputs = [ pkgs.gnused ]; } ''
        sed -E 's|^[[:space:]]*//.*||g; s|//.*||g' ${file} > $out
      '';
      toSettingsFromDrv = name: drv: builtins.fromJSON (builtins.readFile (toPureJsonFile name drv));
    in {
      disableTelemetry = toSettingsFromDrv "disable-telemetry" (pkgs.fetchurl {
        url = "https://raw.githubusercontent.com/fencesandbox/fence/refs/tags/v0.1.67/internal/templates/disable-telemetry.json";
        hash = "sha256-GHL7/GjioaCTvl0NUyC2E+nqO3BBL7QfI8WrKX9vacE=";
      });
      gitReadOnly = toSettingsFromDrv "git-readonly" (pkgs.fetchurl {
        url = "https://raw.githubusercontent.com/fencesandbox/fence/refs/tags/v0.1.67/internal/templates/git-readonly.json";
        hash = "sha256-CggaCxO6Du65zLvJH+3y3KS3I8aNTrjI4soFd95RIkk=";
      });
    };
  defaultProfiles = {
    yolo = {
      settings = lib.my.deepMerge {
        extends = "code"; # https://github.com/fencesandbox/fence/blob/main/internal/templates/code.json
      } templates.disableTelemetry;
    };

    default = {
      default = true;
      settings = {
        extends = "./yolo.json";
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
  # and runnable inside the sandbox, the state directories the agents and tools
  # write must stay writable, and the AI providers plus MCP hub servers the
  # harness is configured with must stay reachable.
  settingsForNixEnv = {
    "$schema" = "https://raw.githubusercontent.com/fencesandbox/fence/main/docs/schema/fence.schema.json";
    filesystem = {
      allowRead = ["/nix/store"];
      allowExecute = ["/nix/store"];
    };
    command.acceptSharedBinaryCannotRuntimeDeny = coreutilsCommands;
  }
  // settingsForNetwork;

  finalProfiles = lib.mapAttrs' (name: entry: {
    inherit name;
    value = lib.my.deepMerge entry { settings = settingsForNixEnv; };
  }) cfg.harness.sandbox.profiles;

  # Every profile is reachable without a typed path: the alias points at the
  # rendered file by its XDG path rather than by profile name, because `--settings`
  # takes a path and the profile name alone does not tell Fence which file to read.
  # The long flag is spelled out because the alias is read far more often than it
  # is written, and it is the only place `--settings` appears in the shell.
  profileAliases = lib.mapAttrs' (name: _: {
    name = "fence-${name}";
    value = "fence --settings ${config.xdg.configHome}/fence/${name}.json";
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
              profile needs: the schema URL, read and execute access to
              `/nix/store`, write access to the state directories the enabled
              agents and harness tools keep, and network access to the providers
              in `my.home.ai.providers` plus the servers in
              `my.home.mcp.hub.client.servers`. Rendered as JSON for Fence, see
              https://github.com/fencesandbox/fence/blob/main/docs/configuration.md

              Each profile also gets a `fence-<name>` shell alias running
              `fence --settings <configHome>/fence/<name>.json`, so the profile can
              be started without typing the path.
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

        One `fence-<name>` alias is added per profile, so `fence-default` starts
        Fence with that profile's settings file.
      '';
    };
  };
  config = lib.mkIf (cfg.harness.enable && cfg.harness.sandbox.enable) {
    home.packages = with pkgs; [
      fence
    ];

    programs.bash.shellAliases = profileAliases;

    programs.fish.shellAbbrs = profileAliases;

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
