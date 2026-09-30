# The gateway has no configuration file of its own: everything it needs reaches
# it through the systemd unit. That makes the unit the only place the decisions
# are observable, so the assertions below read the generated unit rather than a
# rendered file.
#
# What is worth pinning:
#
#   - `central proxy start` forks into the background and exits, so the unit has
#     to be `oneshot` with `RemainAfterExit`. A `simple` unit would track a
#     process systemd never sees and consider the service dead on start.
#   - the port has to arrive as `WIRE_PROXY_PORT`, the only documented override
#     upstream takes, and it belongs to the unit rather than the session.
#   - the unit must be wired into `default.target`, otherwise enabling the option
#     installs a package and a unit that never start.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.home.ai.gateways.jetbrainsCentral;

  unit = config.systemd.user.services.jetbrains-central-gateway;
  service = unit.Service;
  environment = service.Environment or [ ];

  hasEnv = name: lib.any (entry: lib.hasPrefix "${name}=" entry) environment;

  # Matched on the command tail rather than a full store path, so the assertion
  # is about which subcommand systemd runs and does not drag the package
  # derivation's context into the comparison.
  centralBin = "${pkgs.my.jetbrains-central-cli}/bin/central";
  runsProxyStart = service.ExecStart == "${centralBin} proxy start";
  runsProxyStop = service.ExecStop == "${centralBin} proxy stop";

  # A package's store name carries its pname, so matching on the name works
  # whether the entry is a derivation or a symlinkJoin without touching
  # `pname` on a value that may not have one.
  installed = p: lib.any (entry: lib.hasInfix p entry.name or false) config.home.packages;
in
{
  config = {
    # The gateway option lives under `my.home.ai` but is deliberately not gated
    # on `ai.enable`: turning on the parent would pull in every agent option this
    # test does not configure, and the gateway does not need any of them.
    my.home.ai.gateways.jetbrainsCentral = {
      enable = true;
      # A non-default port so the assertion cannot pass for a unit that hardcoded
      # upstream's 19516 instead of reading the option.
      port = 19517;
      extraEnv = {
        HTTP_PROXY = "http://corp.example:3128";
      };
    };

    assertions = [
      {
        assertion = installed "jetbrains-central-cli";
        message = "enabling the gateway must install the central binary; wired agents shell out to it to start the proxy.";
      }
      {
        assertion = service.Type == "oneshot" && service.RemainAfterExit == true;
        message = "`central proxy start` exits after forking, so the unit must be oneshot with RemainAfterExit rather than a long-running Type.";
      }
      {
        assertion = runsProxyStart;
        message = "the gateway unit must start the proxy through `central proxy start`.";
      }
      {
        assertion = runsProxyStop;
        message = "the gateway unit must stop the proxy through `central proxy stop`; a start without a stop leaves a daemon behind on logout.";
      }
      {
        assertion = hasEnv "WIRE_PROXY_PORT";
        message = "the proxy port must reach the unit as WIRE_PROXY_PORT, the only override upstream documents.";
      }
      {
        assertion = lib.any (entry: entry == "WIRE_PROXY_PORT=19517") environment;
        message = "WIRE_PROXY_PORT must carry the configured port, not upstream's default.";
      }
      {
        # Scoping the port to the unit is the difference between a gateway
        # option and a session-wide environment variable, so the session must
        # not see it either.
        assertion = !(config.environment.variables ? WIRE_PROXY_PORT);
        message = "WIRE_PROXY_PORT belongs to the gateway unit, not the session environment.";
      }
      {
        assertion = hasEnv "HTTP_PROXY" && lib.any (entry: entry == "HTTP_PROXY=http://corp.example:3128") environment;
        message = "extraEnv must reach the unit as systemd Environment entries.";
      }
      {
        assertion = lib.elem "default.target" unit.Install.WantedBy;
        message = "the gateway must be enabled in default.target, or enabling the option produces a unit that never starts.";
      }
      {
        # The proxy is a per-user listener reached by agents on the same host.
        assertion = cfg.port >= 1024;
        message = "the gateway port must be unprivileged.";
      }
    ];
  };
}
