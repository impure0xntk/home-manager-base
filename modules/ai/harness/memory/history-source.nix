# Shared builder every agent uses to expose its own session history to ctx.
#
# Each agent module owns its source description and calls `mkHistorySource`
# with it, rather than publishing into a registry that `harness/memory`
# collects afterwards. That split is load bearing: the module declaring
# `harness.memory.historySources` cannot read that same set back out of
# `config` -- asking for any option under a prefix forces every definition
# under it to be merged, including this module's own contribution, which
# evaluated as infinite recursion. One entry point taking explicit arguments
# has no such edge, and each agent already knows its own exporter.
#
# Callers pronounce their requirements in the attribute set below; nothing
# here reads `config`.
{ lib, pkgs }:
rec {
  # Nested `history_sources` list with `schema_version: 2` is the only shape
  # ctx 2.2.8 parses. A flat manifest measures as `status: invalid, error: parse
  # history source plugin manifest`, which silently makes the source
  # non-importable. `enabled` and `refresh` are discovery metadata only: they do
  # not opt a plugin into `ctx import --all`, hence the explicit import below.
  mkManifest =
    source:
    {
      schema_version = 1;
      name = source.providerKey;
      display_name = "${source.displayName} Session History";
      version = "1.0.0";
      history_sources = [
        ({
          id = source.sourceId;
          provider_key = source.providerKey;
          source_id = source.sourceId;
          source_format = source.sourceFormat;
          path = source.path;
          enabled = true;
          refresh = "manual";
        }
        // lib.optionalAttrs (source.lineageContract != null) {
          lineage_contract = source.lineageContract;
        })
      ];
    };

  # Real sibling files rather than symlinks: the manifest and its exporter have
  # to be walkable together, and the codex precedent in `plugins.nix` shows these
  # trees get copied rather than followed.
  mkSourceDir =
    source:
    pkgs.linkFarm "ctx-plugin-${source.providerKey}" ([
      {
        name = "ctx-history-plugin.json";
        path = pkgs.writeText "ctx-history-plugin-${source.providerKey}.json" (
          builtins.toJSON (mkManifest source)
        );
      }
    ]
    ++ lib.optional (source.exporter != null) {
      name = "ctx-history-export";
      path = source.exporter.script;
    });

  # One finite worker, never a supervisor: it produces the file, registers it
  # through the same acquisition path a later daemon refresh uses, and exits.
  # `--history-source` rather than `--all`, because the 1.0 plugin route is
  # excluded from `--all`.
  mkUnit =
    package: source:
    let
      # Exporters read their destination from the environment, not argv: the
      # zerostack exporter takes no arguments at all.
      exporterEnv =
        lib.optionalAttrs (source.exporter != null) (
          { ${source.exporter.outputEnvVar} = source.path; } // source.exporter.environment
        );
      script = pkgs.writeShellScript "ctx-history-${source.providerKey}" ''
        set -euo pipefail
        ${lib.optionalString (source.exporter != null) ''
          ${lib.escapeShellArg source.exporter.interpreter} \
            ${lib.escapeShellArg source.exporter.script}
        ''}
        exec ${lib.getExe package} \
          import --history-source ${lib.escapeShellArg "${source.providerKey}/${source.sourceId}"}
      '';
    in
    {
      services."ctx-history-${source.providerKey}" = {
        Unit.Description = "Refresh ${source.displayName} history in ctx";
        Service = {
          Type = "oneshot";
          ExecStart = toString script;
          Environment = lib.mapAttrsToList (name: value: "${name}=${value}") exporterEnv;
          TimeoutStartSec = "1min";
          # A wedge must fail visibly once, not become a retry loop: the timer
          # already owns the cadence.
          Restart = "no";
        };
      };
      timers."ctx-history-${source.providerKey}" = {
        Unit.Description = "Periodic refresh of ${source.displayName} history";
        Timer = {
          OnCalendar = "hourly";
          Persistent = "true";
        };
        Install.WantedBy = [ "timers.target" ];
      };
    };

  # Fields a caller may set, and what stands in for the ones it leaves alone:
  #
  # - `providerKey` (required): stable lowercase ASCII provider identity. Half
  #   of the `provider_key/source_id` route used after import, and it has to
  #   match the `provider_key` the exporter writes into its JSONL source
  #   record. It is also the plugin directory name, so `ctx sources` route
  #   names stay stable even when the attribute name changes.
  # - `sourceFormat` (required): the format the exporter declares, for example
  #   `zerostack-session-json-v1`. Must match the `source_format` written into
  #   the JSONL source record, or import rejects the durable file.
  # - `sourceId`: defaults to `default`.
  # - `displayName`: human readable name shown by `ctx sources`; defaults to
  #   the provider key.
  # - `path`: absolute path to the durable provider-owned regular file holding
  #   exported `ctx-history-jsonl-v2` records. It must lie **outside** ctx's
  #   data root: `ctx import --history-source` rejects a provider source root
  #   that overlaps or contains the data root itself -- measured on ctx 2.2.8
  #   as `provider source root "<dataRoot>/<providerKey>-history/history.jsonl"
  #   is unsafe relative to ctx data root "<dataRoot>": provider source root
  #   overlaps or contains the ctx data root`. That is why the default sits
  #   under `/tmp` rather than next to the index. `/tmp` also matches the
  #   fallback both bundled exporters already carry, so a source whose
  #   environment variable never reaches them still describes the file they
  #   would have written. Unlike the installer-visible data root this path is
  #   never relocated, so it is a plain string rather than a store path.
  # - `lineageContract`: declares typed relationship and copied-event
  #   authority. It has to match the durable JSONL manifest record exactly, and
  #   neither bundled exporter emits it, so leaving this null is what works
  #   today. Opt in on both sides together or the import rejects the file.
  # - `exporter`: how history reaches `path`. Null means another unit already
  #   writes it and only the periodic import is scheduled. Its `script` carries
  #   a shebang, but the store installs it 0555 without its own interpreter on
  #   PATH, so `interpreter` runs it; both bundled exporters are Python, hence
  #   the default. `outputEnvVar` names the destination, because exporters read
  #   it from the environment rather than argv.
  #
  # `displayName` and the exporter's `interpreter` spell their own defaults
  # here rather than in an option type: each references a sibling value, so a
  # submodule `default` would see neither. Both default to null rather than
  # being absent, so `or` would preserve the null.
  normalize =
    source:
    let
      defaultPath = "/tmp/ctx-${source.providerKey}-history.jsonl";
      exporterDefaults = {
        interpreter = lib.getExe' pkgs.python3 "python3";
        outputEnvVar = "CTX_HISTORY_PATH";
        environment = { };
      };
    in
    {
      inherit (source) providerKey sourceFormat;
      sourceId = source.sourceId or "default";
      displayName = if source.displayName or null != null then source.displayName else source.providerKey;
      path = if source.path or null != null then source.path else defaultPath;
      lineageContract = source.lineageContract or null;
      exporter =
        if source.exporter or null == null then
          null
        else
          exporterDefaults // source.exporter;
    };

  # Everything one source contributes, keyed off nothing but its own arguments:
  # the plugin manifest plus exporter installed together under
  # `ctx/plugins/<providerKey>`, and the finite worker with its hourly timer.
  mkHistorySource =
    { package, source }:
    let
      resolved = normalize source;
      unit = mkUnit package resolved;
    in
    {
      xdg.dataFile."ctx/plugins/${resolved.providerKey}".source = mkSourceDir resolved;
      systemd.user = unit;
    };
}
