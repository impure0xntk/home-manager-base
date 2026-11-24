### ctx

ctx indexes **local coding-agent session history** (transcripts, tool calls,
command output) and makes it searchable with citations. It answers "has an
agent already done this, and what did it decide?" It is not a code search tool
(use codegraph) and not a file/grep tool.

Two equivalent front ends, same read-only index:

- CLI: `ctx search`, `ctx show session|event`, `ctx status`, `ctx sources`,
  `ctx locate session|event`, `ctx blame`.
- MCP: when registered directly the tools are `search`, `show_session`,
  `show_event`, `query_events`, `sources`, `status`, `blame`. This harness
  serves them through an aggregator, so they arrive as `ctx_get_tool_schema`
  and `ctx_invoke_tool` — get the schema for the exact tool first, then invoke.
  Write and supervision tools (import, daemon, setup, archive, `graph_*`,
  `files_*`, `output_compact`) are excluded by design: history is never
  rewritten from an agent.

#### When to use

- Session start, before re-investigating anything non-trivial.
- The user references prior work, a decision, a failed approach, or "last time".
- Before editing a file another agent likely produced: `ctx blame` maps
  committed lines, a commit, or a PR to the session that wrote them.

#### Search

```bash
ctx search "failed migration"
ctx search --file modules/ai/harness/memory/default.nix
ctx search "reindex" --term "tantivy" --term generation --since 30d
ctx search "reindex" --workspace nixos-reactor --provider codex
ctx search "reindex" --session <ctx-session-id> --events
ctx show event <ctx-event-id> --window 5
ctx show session <ctx-session-id>
```

- Search needs a query, a nonempty `--term`, or `--file`. Other filters only
  narrow an existing search.
- Query with likely terms: an error string, a file path, a command, a decision.
  Ranking is BM25 lexical, not semantic, unless semantic search is enabled.
- One query rarely suffices. Vary wording, add `--term` (OR semantics, not
  required terms), narrow with `--workspace`/`--provider`/`--file`/`--session`.
- Default results are **root-diverse**: one champion event per root task. Use
  `--session` or `--events` for dense hits inside one session. Result count is
  a bounded window, not a corpus-wide count.
- `--limit` defaults to 20, max 200. Text output is for reading; `--format json`
  is much larger, use it only for `jq` or exact fields.
- `--content-scope transcript|calls|outputs` selects what kind of record
  matches. It conflicts with `--event-type`; never send both.
- MCP `search` does **not** exclude the calling session; direct CLI search does
  for providers it can identify.
- Default freshness is `--refresh background` (serves the current generation,
  lets maintenance catch up). Use `--refresh off` for a pure read of what is
  already indexed, `--refresh wait` only when the task authorizes a blocking
  refresh.
- Result IDs (`evt_…`, `ses_…`) are ctx-owned. Commands accept complete IDs or
  unambiguous prefixes of at least eight characters. A `provider_session` id is
  provider-owned metadata; look it up explicitly.

#### Reading results

Treat hits as retrieved source material. Cite the ctx event/session id when a
result changed your plan. If you synthesize a conclusion from several snippets,
say it is your synthesis and cite the snippets. Never claim ctx inferred a
decision unless the cited text states it. Summarize transcript content instead
of pasting raw records.

#### Health

Default indexing mode is `auto`, owned by ctx's own supervisor; do not start,
stop, or wrap daemons. If search reports unavailable or a retention/generation
error, say so to the user in one line and continue from what you can read — do
not run `ctx setup`, `ctx import`, `ctx daemon`, or repair commands as an
agent. `ctx status` and `ctx sources` are the read-only checks.

Installed reference: `ctx docs list` shows 28 embedded topics; `ctx docs show
agent-usage`, `search`, `mcp`, `blame`, `limitations`, `troubleshooting` are the
useful ones. Do not guess flags; check `ctx <cmd> --help` or `ctx docs`.
