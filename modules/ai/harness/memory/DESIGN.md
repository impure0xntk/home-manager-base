# Refactor plan: `my.home.ai.harness.memory`

Status: draft. No Nix code written yet.

Move the ctx-related options and wiring out of `harness.codingAgentTools.ctx`,
`harness/tools/default.nix` and `agents/zerostack.nix` into one dedicated
`my.home.ai.harness.memory` namespace with its own module tree.

## Why

ctx has grown past being one entry in a flat tool map. It is the only tool in
`codingAgentTools` that owns mutable state, a background service, a plugin
directory and a per-agent exporter script, and every one of those currently
lives somewhere else:

| Concern | Today | File |
| --- | --- | --- |
| Package and env | `codingAgentTools.ctx.package` | `harness/tools/default.nix:88` |
| MCP surface and tool filters | `codingAgentTools.ctx.mcpServer` | `harness/tools/default.nix:95` |
| Prompt fragment | `codingAgentTools.ctx.prompt` | `harness/tools/CTX.md` |
| Background service | inline `systemd.user.services.ctx-history` | `harness/tools/default.nix:136` |
| zerostack exporter unit plus timer | inline `systemd.user` | `agents/zerostack.nix:255` |
| zerostack plugin manifest and script | `xdg.dataFile."ctx/plugins/zerostack"` | `agents/zerostack.nix:253` |
| zerostack plugin content | directory | `harness/tools/ctx/plugins/zerostack/` |
| jcode plugin content | **untracked, referenced from nothing** | `harness/tools/ctx/plugins/jcode/` |

So adding a second history source means editing three unrelated files and
copying the service block. This refactor gives each concern one home.

## Observed current state

Measured on `home-desktop`, ctx 2.2.8, `CTX_DATA_ROOT=/home/nixos/.local/share/ctx`.

### Nothing outside the module tree touches these options

No hit for `codingAgentTools` in `machines/`, `profiles/` or
`submodules/nixos-base`. The only in-tree readers of the ctx option path are
`harness/tools/default.nix:138` and `agents/zerostack.nix:257`. There is nothing
to migrate in machine configs, so `mkRenamedOptionModule` buys nothing and is
not planned.

### Two history sources, one of them broken

`ctx sources --format json`:

| plugin | path | status | reason |
| --- | --- | --- | --- |
| jcode | `%CTX_DATA_ROOT%/jcode-history/history.jsonl` | `available`, `importable: true` | |
| zerostack | `/tmp/ctx-zerostack-history.jsonl` | `missing`, `importable: false` | the declared provider-owned durable source path is not a regular non-symlink file |

The zerostack row was absence, not location: nothing in this repo wrote the
file at all. The durable-file requirement still holds once it is written.
Location is then constrained the other way, see below: a provider source root
may not overlap or contain the data root, so `%CTX_DATA_ROOT%/...`, which
looked like the correct answer when jcode alone was measured, is rejected
outright for any source this module exports.

### The index is broken by double supervision

`ctx status` / `ctx doctor`:

```
Search   unavailable (generation verification failed)
Refresh  partial (automatic retry daemon unavailable)
Daemon   stale lock (daemon owner identity mismatch)
Blame    Index unavailable -- retained Core snapshot path failed safety validation
  5 issues found
ctx search ... -> the durable generation-retention lease is malformed,
                 non-canonical, or not owner-private
```

Root cause is conflicting supervision of one data root:

- `config.toml` says `[indexing] mode = "auto"` (ctx default). In auto mode ctx
  installs and repairs its own supervisor and expects to own the daemon.
- `harness/tools/default.nix:136` separately declares
  `systemd.user.services.ctx-history` with `Type=simple`,
  `ExecStart=ctx daemon run`, `Install.WantedBy=default.target`. That is a
  second persistent daemon over the same root.

The unit was correctly commented for ctxrs/ctx#1030 (the persistent scheduler
can retry a stuck generation forever), but `simple` plus `default.target` is a
persistent unit, so it cannot express the "one finite worker instead" intent it
documents. No `ctx.timer` exists, confirming there is no finite-work path today.

`daemon/status.json` agrees: `pid 1328`, `start_mode manual`, `status running`,
while that pid no longer exists, hence the stale owner identity.

### No semantic search configured

`status.json`: `semantic_enabled: false`, `semantic_runtime_active: false`,
`semantic_executor: builtin`. Nothing enables it today; the refactor should not
start without it.

### Machinery facts the design depends on

- `ctx import --history-source <plugin>/<source>` is the only plugin import
  route. It does **not** run from `ctx import --all`, from `ctx setup`, or from
  automatic refresh. Each plugin needs an explicit import after its durable path
  exists.
- After import, search filters use the canonical `provider_key/source_id`
  identity (`zerostack/default`), not the `plugin/source` import alias.
- `[indexing] mode` has exactly two values: `auto` and `manual`.
  `ctx index mode <value>` persists into `config.toml`.
- `CTX_DAEMON_ENABLED=false` is a documented **process-level** manual-mode
  override; it wins over persistent shutdown control but does not rewrite
  `config.toml`. It is the safe knob for a wrapped package.
- An accepted import registers the provider file with the normal Core refresh
  path, so any later daemon mode can refresh it.
- Manifests are discovered from `$CTX_DATA_ROOT/plugins/<plugin>/ctx-history-plugin.json`
  and executed never; `CTX_HISTORY_PLUGIN_PATH` is the alternative discovery
  list.
- `%CTX_DATA_ROOT%` is **not** expanded. Measured: a manifest written with
  `"path": "%CTX_DATA_ROOT%/probe-history/history.jsonl"` and passed via
  `CTX_HISTORY_PLUGIN_PATH` came back as
  `<manifest-dir>/%CTX_DATA_ROOT%/probe-history/history.jsonl`,
  `status: missing`, `provider_source_authority: false`. ctx treats a relative
  `path` as relative to the manifest directory, so the prefix becomes a literal
  directory component. The tracked jcode manifest already avoids this: it spells
  the absolute `/home/nixos/.local/share/ctx/jcode-history/history.jsonl`.

### `lean-ctx` is unrelated

`machines/oci-arm/default.nix:240` sets `my.home.ai.proxy.compression.lean-ctx.enable`.
That is a LiteLLM gateway compression toggle sharing three letters with this
tool. Nothing connects the two; the design should say so out loud so a later
reader does not merge them.

## Target layout

```
modules/ai/harness/memory/
  DESIGN.md             this file
  default.nix           options + projection into codingAgentTools
  indexing.nix          background maintenance strategy
  history-sources.nix   plugin registry: manifest, unit, timer generation
  CTX.md                prompt fragment, moved from tools/CTX.md
  plugins/
    jcode/              moved from tools/ctx/plugins/jcode/
    zerostack/          moved from tools/ctx/plugins/zerostack/
```

`modules/ai/harness/tools/ctx/` disappears entirely. `harness/tools/default.nix`
loses the ctx package definition and the inline `ctx-history` service.
`agents/zerostack.nix` loses about 40 lines of systemd and `xdg.dataFile`, keeping
only one `historySources` attribute. `agents/jcode.nix` gains the same, bringing
the currently orphaned jcode plugin under Nix control.

## Option design

```nix
my.home.ai.harness.memory = {
  enable = mkEnableOption "..." // default true when harness.enable;
  dataRoot = readOnly path, "${config.xdg.dataHome}/ctx";
  package = readOnly package;          # wrapped ctx, env set here
  prompt  = nullOr str, CTX.md;
  indexing = { mode, schedule, serviceTuning };
  mcp = { enable, excludeTools };
  historySources = attrsOf (submodule { providerKey, sourceFormat, displayName, path, exporter, refresh, importOnInstall });
};
```

### `indexing.mode`

Two values, mirroring ctx's own vocabulary. **Decision: default `auto`.**

**`auto` (default)**

- Generate **no** systemd unit at all. Hand the root to ctx's own supervisor and
  let it install and repair itself. This deletes the second daemon that broke the
  current root rather than re-expressing the same conflict in a cleaner unit.
- The wrapped package must **not** set `CTX_DAEMON_ENABLED=false`, or the wrapper
  fights the supervisor self-repair it is supposed to enable.
- Do **not** write `config.toml` from home-manager. ctx owns that file and
  rewrites it; writing it declaratively reproduces exactly the double-ownership
  bug being fixed here. `auto` is ctx's own default, so leaving the file alone
  already yields the requested mode and lets ctx keep sole ownership.

**`manual`**

- Wrapped package sets `CTX_DAEMON_ENABLED=false`, so no ctx process can start a
  persistent daemon even when asked.
- `ctx setup --no-daemon` runs as a `Type=oneshot` unit, with a companion timer
  driving one finite Core worker per tick.
- The mode is persisted by running `ctx index mode manual`, not by writing
  `config.toml`, for the ownership reason above.
- This matches the ctxrs/ctx#1030 intent already written in the current comment
  and keeps the result auditable with systemd, at the cost of owning the cadence
  in Nix.

Today `config.toml` already says `auto` while home-manager's unit contradicts it,
which is precisely the split reported as `daemon: stale lock`. `auto` resolves it
by removing the contradiction instead of reconciling it.

`indexing.schedule` and `indexing.serviceTuning` carry what is currently
hardcoded (`Restart = no`, `CPUQuota = 50%`, `Nice = 10`,
`IOSchedulingClass = idle`, `TimeoutStartSec = 30min`, hourly for zerostack) so
the CPU-burn guard stays visible instead of buried in a service body. Both are
**`manual`-only**: they configure units that `auto` does not generate, so
setting them under `auto` must either be inert or fail. Inert options that look
accepted are how the current unit ended up contradicting `config.toml`, so these
should assert rather than silently no-op.

### `historySources`

One attribute per plugin; the module derives everything else.

```nix
harness.memory.historySources.zerostack = {
  providerKey  = "zerostack";
  sourceFormat = "zerostack-session-json-v1";
  exporter.script = ../plugins/zerostack/zerostack-ctx-export;
  refresh.onCalendar = "hourly";
};
```

Derived per entry:

- `ctx-history-plugin.json`, generated from the options rather than hand-written,
  with `path` baked to the **absolute** `/tmp/ctx-<name>-history.jsonl`. It has
  to point outside the data root: `ctx import --history-source` measures
  `provider source root "<dataRoot>/<name>-history/history.jsonl" is unsafe
  relative to ctx data root "<dataRoot>": provider source root overlaps or
  contains the ctx data root`, and fails the unit. `/tmp` is also what both
  bundled exporters fall back to, so the unit and the script cannot disagree.
- **Do not emit `lineage_contract`.** The doc requires it to exactly match the
  durable JSONL manifest record, and neither exporter writes it (verified: both
  emit only `schema_version`, plus `producer`). Declaring it in the plugin
  manifest against a JSONL that omits it would be rejected. It stays opt-in per
  exporter, opting in from both sides together.
- `xdg.dataFile."ctx/plugins/<name>"` installed as real files. Note the existing
  codex precedent in `plugins.nix`: ctz agents copy rather than follow symlinks
  for their own tree, and the same caution applies to `$CTX_DATA_ROOT/plugins`.
- One `<name>-ctx-history.service` running the exporter then
  `ctx import --history-source <providerKey>/default`, plus its timer. This
  exists because plugin sources are explicitly excluded from `ctx import --all`.

This gives zerostack a durable file the unit actually writes, and keeps both
source roots out of the data root.

### `mcp`

The exclusion list currently sits at `harness/tools/default.nix:98`:

- `graph_*` (6 tools) delegated to codegraph
- `output_compact`, `output_restore` delegated to rtk

Keep them, but make the reason declarative. Note the constraint already
documented in `mcp.nix`: `mcp-compressor` accepts one process-wide
`--include-tools` / `--exclude-tools` pair, merged across every backend and
matched literally, so two backends exposing the same tool name cannot be
filtered apart.

## Relationship to `codingAgentTools`

`harness/mcp.nix` treats `codingAgentTools.<tool>.mcpServer` as the single source
of truth and projects it into `mcpServers`, which is what codex, goose, jcode,
junie, qwen and zerostack all translate into their own config format. Breaking
that edge drops MCP registration for every agent at once.

So `codingAgentTools.ctx` stays as a thin projection, not a definition:

```nix
codingAgentTools.ctx = {
  package = cfg.package;
  prompt  = cfg.prompt;
  mcpServer = lib.optionalAttrs cfg.mcp.enable {
    command = lib.getExe cfg.package;
    args = [ "mcp" "serve" ];
    excludeTools = cfg.mcp.excludeTools;
  };
};
```

`home.packages` currently installs `builtins.attrValues codingAgentTools`,
so keeping the projection also keeps ctx on PATH with no second install site.

## Ordered implementation steps

1. Add `harness/memory/` with `default.nix` declaring `enable`, `dataRoot`,
   `package`, `prompt`, and the `codingAgentTools.ctx` projection. Move
   `CTX.md`. Delete the ctx block from `harness/tools/default.nix`. Verify the
   MCP registry still registers identically across agents.
2. Move both plugin directories under `harness/memory/plugins/`.
   Tracked and untracked both: this is also where the orphaned jcode plugin gets
   adopted.
3. Add `indexing.nix`. Land `manual` mode first: `CTX_DAEMON_ENABLED=false` in
   the wrapper, `Type=oneshot` setup unit plus timer, and persist the mode into
   `config.toml`. Add the assertion barring `auto` from also declaring a unit.
4. Add `history-sources.nix` with generated manifests. Port zerostack onto it
   and delete its ~40 lines from `agents/zerostack.nix`; add the jcode entry.
5. Repair the live root, in order: stop the foreign unit, clear the stale
   daemon lock, drop the old broken source registration (its path sits inside
   the data root, so it must be dropped rather than rewritten there), then run
   `ctx import --history-source zerostack/default` and confirm `ctx status`.
   This step mutates private search history, so it wants explicit go-ahead.
6. Add `filesystem.allowWrite` for `dataRoot` to the fence baseline in
   `harness/sandbox/default.nix`. `settingsForNixEnv` grants read and execute
   over `/nix/store` and friends but no write beyond what the profile sets, and
   ctx writes inside its own data root, so today a sandboxed agent gets read-only
   history.
7. Build both machines (`home-desktop`, `office-laptop`) and diff the generated
   units against the current generation before switching.

## Side effects to expect

- The old `ctx-history.service` is replaced. A live one holding a stale lock has
  to be stopped before the new one starts.
- Old registrations pointed into the data root. They have to be dropped, not
  merely rewritten in place, or the containment check keeps rejecting the unit.
- `history.jsonl` files contain private prompts and tool output. Both exporters
  already chmod 0600 and 0700 their output; keep that.
- `machines/oci-arm` keeps pointing at `lean-ctx`, unchanged.

## Open questions

1. **Default for `indexing.mode`.** `manual` keeps control and CPU-visible
   cadence with systemd; `auto` is less Nix code and gets the daemon install and
   self-repair upstream maintains. Which is preferred?
2. **Keep `codingAgentTools.ctx` as a projection, or delete it outright?**
   Projection preserves the MCP registry with no change to six agent modules.
   Deleting it means rewriting how each agent discovers ctx, and `mcp.nix` stops
   being uniform.
3. **Adopt the untracked jcode plugin** as part of this refactor, or leave it
   until the rest lands? Its installed manifest is already absolute and correct,
   so it imports and searches today. Porting it means rewriting that working
   manifest to the generated form; leaving it late carries less risk, but it
   leaves the tree in a state `git status` flags.
