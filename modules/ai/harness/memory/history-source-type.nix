# Option type for one local tool whose history ctx imports.
#
# Kept in a plain (non-module) file so both `harness/memory/default.nix` (option
# declaration) and `harness/memory/history-sources.nix` (derived units) can
# import it, the same reason `harness/mcp-server-type.nix` exists. `pkgs` reaches
# it from the importing module for the one default that needs a store path.
{ lib, pkgs, ... }:

lib.types.submodule {
  options = {
    providerKey = lib.mkOption {
      type = lib.types.str;
      description = ''
        Stable lowercase ASCII provider identity. It is half of the
        `provider_key/source_id` route used after import, and must match the
        `provider_key` the exporter writes into its JSONL source record. It is
        also the plugin directory name, so `ctx sources` route names stay stable
        even when the attribute name changes.
      '';
    };

    sourceId = lib.mkOption {
      type = lib.types.str;
      default = "default";
      description = "Stable lowercase ASCII source identity within the provider.";
    };

    sourceFormat = lib.mkOption {
      type = lib.types.str;
      description = ''
        Source format the exporter declares, for example
        `zerostack-session-json-v1`. Must match the `source_format` written into
        the JSONL source record, or import rejects the durable file.
      '';
    };

    displayName = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Human readable name shown by `ctx sources`. Defaults to the provider key.";
    };

    # Left null for `history-source-internals.nix` to fill: it cannot be derived
    # here. A `default` in a submodule sees no sibling `providerKey`, and
    # resolving the path outside this submodule forced the same namespace this
    # option lives in to be evaluated while it was still being declared, which
    # is infinite recursion at build time.
    path = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      defaultText = lib.literalExpression ''"/tmp/ctx-''${providerKey}-history.jsonl"'';
      description = ''
        Absolute path to the durable provider-owned regular file holding
        exported `ctx-history-jsonl-v2` records.

        It must lie **outside** the module `dataRoot`: `ctx import
        --history-source` rejects a provider source root that overlaps or
        contains the data root itself -- measured on ctx 2.2.8 as
        `provider source root "<dataRoot>/<providerKey>-history/history.jsonl"
        is unsafe relative to ctx data root "<dataRoot>": provider source root
        overlaps or contains the ctx data root`. That is why the default sits
        under `/tmp` rather than next to the index. Each source's unit writes
        the file before importing it, so a reboot that clears `/tmp` only
        defers the next hourly export. Unlike installer-visible data root, this
        path is never relocated, so it is a plain string rather than a store
        path.
      '';
    };

    lineageContract = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum [ "provider_native_v1" ]);
      default = null;
      description = ''
        Declares typed relationship and copied-event authority. It has to match
        the durable JSONL manifest record exactly, and neither bundled exporter
        emits it, so leaving this null is what works today. Opt in on both sides
        together or the import rejects the file.
      '';
    };

    exporter = lib.mkOption {
      type = lib.types.nullOr (lib.types.submodule {
        options = {
          script = lib.mkOption {
            type = lib.types.path;
            description = ''
              Script writing `ctx-history-jsonl-v2` records. It carries a
              shebang, but the store installs it 0555 without its own
              interpreter on PATH, so `interpreter` runs it.
            '';
          };
          # A real `default`, never a `//` patch downstream: an
          # already-resolved submodule value cannot be overridden later, and the
          # type file has `pkgs` in scope precisely so this can be resolved
          # here. Both bundled exporters are Python, their
          # `#!/usr/bin/env python3` shebang does not resolve inside a unit, and
          # the store installs them 0555 with no interpreter on PATH, so leaving
          # this null puts an empty first argument in ExecStart and the export
          # never runs.
          interpreter = lib.mkOption {
            type = lib.types.path;
            default = lib.getExe' pkgs.python3 "python3";
            defaultText = lib.literalExpression "\"\${pkgs.python3}/bin/python3\"";
            description = "Interpreter used to run `script`.";
          };
          outputEnvVar = lib.mkOption {
            type = lib.types.str;
            default = "CTX_HISTORY_PATH";
            description = ''
              Environment variable naming the destination file. Exporters take
              their destination from the environment rather than argv, so this
              is the whole interface; the zerostack exporter accepts no
              arguments at all.
            '';
          };
          environment = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = { };
            description = ''
              Environment variables set for the exporter only. Exporters read
              their output location from here rather than from argv, because the
              zerostack exporter takes no arguments at all.
            '';
          };
        };
      });
      default = null;
      description = ''
        How history reaches `path`. Null means another unit already writes it,
        and only the periodic import is scheduled.
      '';
    };
  };
}
