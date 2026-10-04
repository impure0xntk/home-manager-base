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

  isLoopbackHost =
    host:
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
      gitReadOnly = toSettingsFromDrv "git-readonly" (pkgs.fetchurl {
        url = "https://raw.githubusercontent.com/fencesandbox/fence/refs/tags/v0.1.67/internal/templates/git-readonly.json";
        hash = "sha256-CggaCxO6Du65zLvJH+3y3KS3I8aNTrjI4soFd95RIkk=";
      });
    };
  defaultProfiles =
    let
      gitReadOnlyStrictCommand = [
        "git commit"
        "git stash"
      ];
      dangerousCommand = [
        # https://github.com/nolabs-ai/nono/blob/e1f84a33bdfecad82490285ea65058fdabe2028a/crates/nono-cli/data/policy.json#L595
        "rm"
        "rmdir"
        "dd"
        "chmod"
        "chown"
        "chgrp"
        "mv"
        "cp"
        "truncate"
        "scp"
        "rsync"
        "sftp"
        "ftp"
        "xargs"
        "sudo"
        "su"
        "doas"
        "pip"
        "npm"
        "kill"
        "killall"
        "pkill"
        "shutdown"
        "reboot"
        "halt"
        "poweroff"

        # https://github.com/nolabs-ai/nono/blob/e1f84a33bdfecad82490285ea65058fdabe2028a/crates/nono-cli/data/policy.json#L639
        "shred"
        "mkfs"
        "mkfs.ext4"
        "mkfs.xfs"
        "mkfs.btrfs"
        "mkswap"
        "fdisk"
        "parted"
        "gdisk"
        "wipefs"
        "chattr"
        "init"
        "systemctl"
        "apt"
        "apt-get"
        "dpkg"
        "yum"
        "dnf"
        "pacman"
        "pkexec"

        # nix
        "switch-to-configuration"
        "nixos-rebuild switch"
        "nixos-rebuild boot"
        "nixos-rebuild test"
        "nixos-install"
        "nixos-enter"
        "nix-env -p /nix/var/nix/profiles/system"
        "nix-env --profile /nix/var/nix/profiles/system"
      ];
    in {
      yolo = {
        settings = {
          extends = "code-relaxed"; # https://github.com/fencesandbox/fence/blob/main/internal/templates/code.json
        };
      };

      default = {
        default = true;
        settings = {
          extends = "code-strict";
          command = {
            deny = gitReadOnlyStrictCommand ++ dangerousCommand;
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
  # and runnable inside the sandbox, the state directories the agents and tools
  # write must stay writable, and the AI providers plus MCP hub servers the
  # harness is configured with must stay reachable.
  settingsForNixEnv = let
    fs = [ # https://github.com/nolabs-ai/nono/blob/e1f84a33bdfecad82490285ea65058fdabe2028a/crates/nono-cli/data/policy.json#L560
      "~/.nix-profile"
      "~/.local/state/nix/profile"
      "~/.local/state/nix/profiles"
      "~/.nix-defexpr"
      "~/.local/state/nix/defexpr"
      "/run/current-system/sw"
      "/etc/profiles/per-user"
      "/nix/var/nix/profiles"
      "/nix/store"
    ];
  in {
    "$schema" = "https://raw.githubusercontent.com/fencesandbox/fence/main/docs/schema/fence.schema.json";
    filesystem = {
      allowRead = fs;
      allowExecute = fs;
    };
    command.acceptSharedBinaryCannotRuntimeDeny = coreutilsCommands;
  }
  // settingsForNetwork;

  finalProfiles = lib.mapAttrs' (name: entry: {
    inherit name;
    value = lib.my.deepMerge entry { settings = settingsForNixEnv; };
  }) cfg.harness.sandbox.profiles;

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
