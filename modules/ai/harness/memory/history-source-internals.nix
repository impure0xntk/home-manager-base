# Helpers behind `harness.memory.historySources`: per-source plugin manifest,
# exporter unit, and the projection tying them into the home.
#
# The one failure `ctx sources` reports against this tree is containment, not
# existence: `ctx import --history-source` refuses a provider source root that
# overlaps or contains its own data root, so every export has to be written
# outside `~/.local/share/ctx`. All of it is derived from options now, so a
# rebuild repairs a wrong path.
#
# `projected` takes every input it needs as an argument instead of accepting the
# whole `harness.memory` set. Requesting that set resolves each option in it, and
# `enable` and `package` are filled by modules that also ask for `historySources`,
# so naming the set here makes a contributor wait on itself: infinite recursion.
# One option at a time, resolved by the module system, keeps each step finite.
{ lib, pkgs }:
rec {
  # Nested `history_sources` list with `schema_version: 2` is the only shape
  # ctx 2.2.8 parses. A flat manifest measures as `status: invalid, error: parse
  # history source plugin manifest`, which silently makes the source
  # non-importable. `enabled` and `refresh` are discovery metadata only: they do
  # not opt a plugin into `ctx import --all`, hence the explicit import below.
  createManifest = source: {
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
  createSourceDir =
    source:
    pkgs.linkFarm "ctx-plugin-${source.providerKey}" ([
      {
        name = "ctx-history-plugin.json";
        path = pkgs.writeText "ctx-history-plugin-${source.providerKey}.json" (
          builtins.toJSON (createManifest source)
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
  createUnit =
    ctxPackage: source:
    let
      # Exporters read their destination from the environment, not argv: the
      # zerostack exporter takes no arguments at all.
      exporterEnv = lib.optionalAttrs (source.exporter != null) (
        { ${source.exporter.outputEnvVar} = source.path; } // source.exporter.environment
      );
    in
    {
      systemd.user.services."ctx-history-${source.providerKey}" = {
        Unit.Description = "Refresh ${source.displayName} history in ctx";
        Service = {
          Type = "oneshot";
          ExecStart = toString (pkgs.writeShellScript "ctx-history-${source.providerKey}" ''
            set -euo pipefail
            ${lib.optionalString (source.exporter != null) ''
              ${lib.escapeShellArg source.exporter.interpreter} \
                ${lib.escapeShellArg source.exporter.script}
            ''}
            exec ${lib.getExe ctxPackage} \
              import --history-source ${lib.escapeShellArg "${source.providerKey}/${source.sourceId}"}
          '');
          Environment = lib.mapAttrsToList (name: value: "${name}=${value}") exporterEnv;
          TimeoutStartSec = "1min";
          # A wedge must fail visibly once, not become a retry loop: the timer
          # already owns the cadence.
          Restart = "no";
        };
      };
      systemd.user.timers."ctx-history-${source.providerKey}" = {
        Unit.Description = "Periodic refresh of ${source.displayName} history";
        Timer = {
          OnCalendar = "hourly";
          Persistent = "true";
        };
        Install.WantedBy = [ "timers.target" ];
      };
    };

  normalize =
    { source }:
    # `displayName` and the exporter's `interpreter` spell their own defaults
    # here rather than in the type: each references a sibling option, and a
    # submodule `default` sees neither. Both default to null rather than being
    # absent, so `or` would preserve the null.
    #
    # `dataRoot` deliberately plays no part: ctx refuses a provider source root
    # that overlaps or contains it. `/tmp` also matches the fallback both
    # bundled exporters already carry, so a source whose environment variable
    # never reaches them still describes the file they would have written.
    let
      defaultPath = "/tmp/ctx-${source.providerKey}-history.jsonl";
    in
      source
      // {
        displayName = if source.displayName != null then source.displayName else source.providerKey;
        path = if source.path != null then source.path else defaultPath;
        exporter = source.exporter;
      };

  # Resolved of its inputs rather than of the declaring namespace, so each piece
  # arrives on demand instead of pulling the set that contains it.
  projected =
    { package, sources }:
    let
      resolved = lib.mapAttrs (_: source: normalize { inherit source; }) sources;
    in
    lib.mkMerge [
      {
        xdg.dataFile = lib.mapAttrs' (
          _: source:
          lib.nameValuePair "ctx/plugins/${source.providerKey}" {
            source = createSourceDir source;
          }
        ) resolved;
      }
      (lib.mkMerge (lib.mapAttrsToList (_: source: createUnit package source) resolved))
    ];
}
