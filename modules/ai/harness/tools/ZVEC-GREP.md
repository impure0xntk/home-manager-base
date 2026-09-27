### zvec-grep

Choose the evidence source before the retrieval mode, and choose the retrieval mode from
the shape of the question rather than from habit.

#### Search routing

One route per question. A second index over the same question is a wasted round trip.

| Question shape | Route |
| --- | --- |
| Exact literal, filename, path, config key, error string, regex, hit count, path list | `zvec_grep_rg` when the host lists it, otherwise `rg` |
| Concept, "how does X work", relationships, chronology, architecture, data or control flow, cross-file comparison | `zvec_grep_search` |
| One symbol, module, package, or the file you are about to edit; callers, callees, import edges | `codegraph_explore` with an explicit `maxFiles` |
| Work a prior session did | `ctx` search |

Never answer a lexical question with `codegraph_explore`: 2.4-5.6x the bytes, and literals inside lists, TOML or JSON array items, and regex patterns are not indexed, so text queries return nothing.

#### Escalation

- Answer the exact question with the exact route first.
- Never run a lexical query and a graph query on the same question, and never re-run one index to confirm the other.
- Escalate to `codegraph_explore` only when the first answer surfaced a symbol whose callers or callees you need.
- A saturated or truncated result is a routing failure: narrow the question, do not repeat the sweep.

#### Workspace evidence

- Use the current workspace as the evidence source when the user asks about local material, prior context establishes it as relevant, or the question concerns how the current project works―even if the workspace is not mentioned explicitly.
- A workspace may contain any mix of code, documents, configuration, and data.
- Do not use workspace retrieval for unrelated open-world questions, current external facts, or web content that does not depend on local evidence.

#### Retrieval routing

- When exact word, phrase, name, date, identifier, filename, path, configuration key, error message, source fragment, literal, or regex is known and locating its occurrences is sufficient, use `zvec_grep_rg` when it is listed by the current host; otherwise native Grep or `rg`.
- Use `zvec_grep_search` when wording or location is unknown, or when the answer requires semantic, conceptual, fuzzy, or paraphrase discovery; relationships, chronology, causality, architecture, or data or control flow; or comparison or synthesis across files, sections, or documents.
- For a mixed task with exact anchors that still requires relationships or cross-file synthesis, call `zvec_grep_search` with the concept and anchors, then use `zvec_grep_rg` when it is listed by the current host; otherwise native Grep or `rg` for focused follow-up.
- When no sufficient exact anchor is available and the user asks whether conceptually related material exists locally, make at most one focused `zvec_grep_search` probe using the question plus distinctive names, dates, or terms. This probe does not apply to exact quotations, configuration keys, filenames, regexes, or exhaustive occurrence requests. Continue only when results are relevant; otherwise stop and report that the indexed workspace did not establish the answer.
- Before broad file reads or delegating workspace discovery, use the appropriate search route. Do not delegate solely to locate material, and stop when the evidence is sufficient.
- MUST use an English query.

#### Search evidence

- Search results include bounded source snippets. Treat a sufficient snippet as already-read evidence, and read a cited file only when a required detail falls outside the snippet.

#### Freshness and index lifecycle

- Pass a daemon-visible absolute `root` on every zvec-grep workspace call.
- Read `freshness` and `background_refresh` from search results without a status preflight.
- When results are `served_from_current_index`, use them when sufficient instead of waiting for the background refresh.
- If the index is missing but exact or regex lookup can answer the task, use `zvec_grep_rg` when it is listed by the current host; otherwise native Grep or `rg`.
- Creating, rebuilding, or dropping a persistent index requires an explicit user request or authorization; never do so silently.
