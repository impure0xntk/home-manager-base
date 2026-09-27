### Codegraph

The codegraph MCP server exposes one tool: `codegraph_explore` (params: `query`, `maxFiles` default 12, `projectPath`).

Use `codegraph_explore` for: one symbol, one module, one package, or the file you are about to edit; definition sites, callers, callees, import edges, dead code; the file set of an area.

Never use it for: exact literals, filenames, config keys, error strings, regexes, hit counts, path lists; string literals inside lists, TOML or JSON array items, and regex data, which are not indexed; workspace-wide sweeps. Use `zvec_grep_rg` when the host lists it, otherwise `rg`.

- Set `maxFiles` explicitly. The default returns the surrounding bindings of every node and saturates near 20-25 KB regardless of hit count, 2.4-5.6x the lexical route on the same question (79 hits: 25200 B vs 10686 B; 40 hits: 20512 B vs 3660 B).
- One index per question. Never call `codegraph_explore` and then grep for the same thing.
- Escalate once: answer the exact question with the exact route first, and call `codegraph_explore` only when that answer surfaced a symbol whose callers or callees you need.
- No results on a text query is a routing signal, not evidence of absence. Switch to the lexical route and say why in your response.
- The tool description calls itself the primary tool for almost any question. That is a default, not a routing rule.
- Treat the source it returns as already read; do not re-open those files.
