{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.home.ai;

  # srt matches `network.allowedDomains` by host name, so a provider URL only
  # becomes an allow rule once reduced to a host. The scheme supplies the port,
  # because the rule is scoped to the port the endpoint is actually reached on:
  # an entry without one matches every port, which would let a sandboxed agent
  # reach an unrelated service on the same host.
  parseProviderUrl =
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

  providerEndpoints = map (provider: parseProviderUrl provider.url) (cfg.providers or [ ]);

  # The AI providers are not the only endpoints a harness session talks to:
  # every agent here also dials the MCP hub servers in `my.home.mcp.hub.client`,
  # and a host srt has no rule for is denied with a proxy 403 before the request
  # is ever made. Deriving the rules from that list too keeps the sandbox in
  # step with the servers the machine actually configures.
  #
  # `servers` has a default, so the option has a value before a machine
  # configures any, and that default is a loopback address on port 3001. A
  # disabled client is what keeps it from being an endpoint: nothing generates a
  # wrapper for it and nothing connects, so allow-listing the port on a machine
  # that never enabled the client would open a real host port for no reason. The
  # gate is on `enable` rather than on the default's value, because that value is
  # a legitimate loopback host a machine can genuinely configure.
  mcpHubEndpoints =
    if config.my.home.mcp.hub.client.enable then
      map (server: {
        inherit (server) host port;
      }) config.my.home.mcp.hub.client.servers
    else
      [ ];

  harnessEndpoints = providerEndpoints ++ mcpHubEndpoints;

  # Every endpoint becomes one `host:port` entry. The port is the point: srt
  # treats an entry without one as matching every port on that host, so a
  # portless entry would also open whatever else runs on the same route.
  #
  # The host is carried through as `separateHostAndPort` spells it, which is the
  # form srt matches. It lower-cases, so an uppercase URL cannot produce an entry
  # that matches nothing, and it keeps an IPv6 literal bracketed, which is the
  # only form srt's schema accepts (RFC 3986) and the one it canonicalizes a
  # destination back to before matching. So `localhost:11434`, `127.0.0.1:11434`
  # and `[::1]:11434` each name the endpoint they were configured as, without a
  # second pass to re-spell any of them.
  networkEntries = lib.unique (
    map (endpoint: "${endpoint.host}:${toString endpoint.port}") harnessEndpoints
  );

  # Every profile reaches the AI backends and the MCP hub servers the harness
  # itself is configured with, so the allow rules are derived from
  # `my.home.ai.providers` and `my.home.mcp.hub.client.servers` rather than
  # listed per profile. srt denies outbound traffic matching no rule, so a
  # machine with no provider and no enabled hub client gets an empty allowlist,
  # which denies every outbound connection and leaves the sandbox as closed as
  # it is useful to be.
  settingsForNetwork = {
    network = {
      allowedDomains = networkEntries;
      deniedDomains = [ ];
      # srt falls back to asking the user when a destination matches no rule,
      # and there is nobody to ask inside a `srt-<profile>` alias: the prompt
      # would read as a hang. The allowlist is the whole policy instead.
      strictAllowlist = true;
    };
  };

  # An agent inside the sandbox is a separate process with its own state: it
  # persists sessions, caches models and stores tool history under the XDG roots
  # the harness points it at. Those roots are not under the working directory, so
  # a profile that only allows the workspace leaves every one of them on the
  # read-only bind and the agent fails to start with EROFS on its first write.
  # Each root is derived from the same option that points the agent or tool at
  # it, so enabling one is what adds its directory and nothing has to be
  # restated per profile.
  #
  # The roots come from the XDG options rather than a literal `~` because `~` is
  # the wrong string the moment a machine relocates `xdg.configHome`, and srt
  # resolves a relative entry against the working directory rather than the
  # user's home.
  agentStateRoots =
    let
      enabled = condition: paths: lib.optionals condition paths;
    in
    lib.unique (
      enabled cfg.jcode.enable [
        # `JCODE_HOME`, plus `~/.cache/jcode` for the LaTeX and Mermaid caches
        # and the transcript renderer, which writes next to it.
        "${config.xdg.configHome}/jcode"
        "${config.xdg.cacheHome}/jcode"
      ]
      ++ enabled cfg.codex.enable [ "${config.xdg.configHome}/codex" ]
      ++ enabled cfg.copilot-cli.enable [ "${config.xdg.configHome}/copilot" ]
      ++ enabled cfg.goose.enable [ "${config.xdg.configHome}/goose" ]
      ++ enabled cfg.qwen-code.enable [ "${config.xdg.configHome}/qwen" ]
      ++ enabled cfg.junie.enable [ "${config.xdg.dataHome}/junie" ]
      ++ enabled (cfg.harness.codingAgentTools.ctx.mcpServer != null) [
        "${config.xdg.dataHome}/ctx"
        "${config.xdg.stateHome}/ctx"
      ]
      ++ enabled (cfg.harness.codingAgentTools.zg.mcpServer != null) [
        "${config.xdg.configHome}/zvec-grep"
        "${config.xdg.dataHome}/zvec-grep"
      ]
      ++ enabled (cfg.harness.codingAgentTools.rtk.package != null) [ "${config.xdg.dataHome}/rtk" ]
    );

  # srt denies every write that matches no rule and mounts the rest read-only,
  # so the state roots are what the profile is actually allowed to write. Its own
  # `filesystem.allowWrite` is merged over these rather than replaced: the
  # workspace and `/tmp` the profile asks for belong to the profile, the state
  # roots belong to every agent the harness enables.
  settingsForFilesystem = {
    filesystem = {
      # Reads are unrestricted by default, so the Nix-provided binaries stay
      # readable and runnable inside the sandbox without a read allowlist, and
      # srt has no execute allowlist to keep in step with one.
      denyRead = [ ];
      allowWrite = agentStateRoots;
      denyWrite = [ ];
    };
  };

  # srt has no profile inheritance, so there is no `extends` entry to name and no
  # template to fetch. The shipped profiles are therefore spelled out rather than
  # layered: one that writes only the workspace, and one that writes anywhere,
  # which is what an agent that runs commands on its own needs. `yolo` is the
  # conventional name for the latter.
  defaultProfiles = {
    cautious = {
      default = true;
      settings = {
        filesystem.allowWrite = [
          "."
          "/tmp"
        ];
      };
    };

    yolo = {
      settings = {
        filesystem.allowWrite = [
          "."
          "/tmp"
          "~"
        ];
      };
    };
  };

  # `default` is kept alongside the merged settings rather than being read back
  # out of them: it is a flag on the profile, not an srt setting, so folding it
  # into the settings object would put a key in the rendered JSON that srt's
  # schema rejects.
  finalProfiles = lib.mapAttrs' (name: entry: {
    inherit name;
    value = {
      isDefault = entry.default or false;
      settings = lib.my.deepMerge {
        network = settingsForNetwork.network;
        filesystem = settingsForFilesystem.filesystem;
      } entry.settings;
    };
  }) cfg.harness.sandbox.profiles;

  # Every profile is reachable without a typed path: the alias points at the
  # rendered file by its XDG path rather than by profile name, because
  # `--settings` takes a path and the profile name alone does not tell srt which
  # file to read. The long flag is spelled out because the alias is read far more
  # often than it is written, and it is the only place `--settings` appears in
  # the shell.
  profileAliases = lib.mapAttrs' (name: _: {
    name = "srt-${name}";
    value = "srt --settings ${config.xdg.configHome}/sandbox-runtime/${name}.json";
  }) cfg.harness.sandbox.profiles;

  defaultProfileNames = lib.attrNames (lib.filterAttrs (_name: entry: entry.isDefault) finalProfiles);

  # A provider URL with neither an explicit port nor a scheme to default it
  # from leaves nothing for the `:port` allow entry to name, and srt rejects the
  # whole settings file over it, so the mistake has to surface at evaluation
  # time rather than as an agent that cannot reach its provider.
  providersWithoutPort = map (provider: provider.name) (
    builtins.filter (provider: (parseProviderUrl provider.url).port == null) (cfg.providers or [ ])
  );
in
{
  options.my.home.ai.harness.sandbox =
    with lib;
    with lib.types;
    {
      enable = mkEnableOption "Whether to enable the AI harness sandbox";
      profiles = mkOption {
        type = attrsOf (submodule {
          options = {
            settings = mkOption {
              type = attrs;
              default = { };
              description = ''
                Settings for the sandbox profile, an srt configuration as
                documented in https://github.com/anthropics/sandbox-runtime#configuration

                Both `network` and `filesystem` are required by srt's schema, so
                the module contributes both and this option is where the values
                that are not derived go. The network allow rules are derived rather
                than listed here: `network.allowedDomains` is built from
                `my.home.ai.providers` and `my.home.mcp.hub.client.servers`, so a
                host a profile adds is merged in but never replaces the endpoints
                the harness is actually configured with.

                `filesystem.allowWrite` is merged with the state directories of the
                enabled agents and harness tools, which every profile needs, so a
                profile's own entries are what it adds on top: `.` is the working
                directory and `/tmp` the scratch the agent is expected to have.
              '';
            };
            default = mkEnableOption ''
              Whether to use this profile as the default profile of the AI
              harness sandbox. Its settings are additionally written to
              `sandbox-runtime/srt-settings.json`, the file srt reads when it is
              started without `--settings` and the one a shell alias points at when
              the profile is started by name. At most one profile may set this.
            '';
          };
        });
        default = defaultProfiles;
        description = ''
          Sandbox runtime profiles. Each profile is written to
          `sandbox-runtime/<name>.json`, and the single profile with
          `default = true` is additionally written to
          `sandbox-runtime/srt-settings.json`, the file srt reads when no
          `--settings` is given.

          One `srt-<name>` alias is added per profile, so `srt-cautious` starts
          sandbox runtime with that profile's settings file.
        '';
      };
    };
  config = lib.mkIf (cfg.harness.enable && cfg.harness.sandbox.enable) {
    home.packages = [
      pkgs.sandbox-runtime
    ];

    programs.bash.shellAliases = profileAliases;

    programs.fish.shellAbbrs = profileAliases;

    xdg.configFile = lib.mkMerge [
      (lib.mapAttrs' (name: entry: {
        name = "sandbox-runtime/${name}.json";
        value.text = builtins.toJSON entry.settings + "\n";
      }) finalProfiles)
      (lib.optionalAttrs (defaultProfileNames != [ ]) {
        "sandbox-runtime/srt-settings.json".text =
          builtins.toJSON finalProfiles.${lib.head defaultProfileNames}.settings + "\n";
      })
    ];

    assertions = [
      {
        assertion = builtins.length defaultProfileNames <= 1;
        message = "my.home.ai.harness.sandbox.profiles: at most one profile may set default = true, but found: ${lib.concatStringsSep ", " defaultProfileNames}";
      }
      {
        assertion = providersWithoutPort == [ ];
        message = "my.home.ai.providers: a provider URL needs an explicit port, or a scheme to default the port from, for srt to allow-list it by host and port: ${lib.concatStringsSep ", " providersWithoutPort}";
      }
    ];
  };
}
