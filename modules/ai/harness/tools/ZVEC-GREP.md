## zvec-grep (CLI: `zg`)

Choose the evidence source before the retrieval mode.

### Workspace evidence

* Use the current workspace as the evidence source when the user asks about local material, prior context establishes it as relevant, or the question concerns how the current project works—even if the workspace is not mentioned explicitly.
* A workspace may contain any mix of code, documents, configuration, and data.
* Do not use workspace retrieval for unrelated open-world questions, current external facts, or web content that does not depend on local evidence.

### Retrieval routing

* When an exact word, phrase, name, date, identifier, filename, path, configuration key, error message, source fragment, literal, or regex is known and locating its occurrences is sufficient: use `zg query --rg [rg-options] <pattern> [path...]` for exhaustive managed ripgrep without an index.
* When wording or location is unknown, or when the answer requires semantic, conceptual, fuzzy, or paraphrase discovery; relationships, chronology, causality, architecture, or data or control flow; or comparison or synthesis across files: use `zg query <query> [options]` for hybrid lexical+vector retrieval, `zg query --vector <query>` for semantic-only, or `zg query --fts <query>` for ranked lexical retrieval.
* For a mixed task with exact anchors that still requires relationships or cross-file synthesis: use `zg query --hybrid <concept> --fts <anchor> [--vector <concept>] [--fuse]` to combine query groups, then use `zg query --rg` for focused follow-up.
* When no sufficient exact anchor is available and the user asks whether conceptually related material exists locally: make at most one focused probe using `zg query <query>` or `zg query --vector <query>` with the question plus distinctive names, dates, or terms. This probe does not apply to exact quotations, configuration keys, filenames, regexes, or exhaustive occurrence requests. Continue only when results are relevant; otherwise stop and report that the indexed workspace did not establish the answer.
* Before broad file reads or delegating workspace discovery, use the appropriate search route. Do not delegate solely to locate material, and stop when the evidence is sufficient.

### Search evidence

* Search results include bounded source snippets. Treat a sufficient snippet as already-read evidence, and read a cited file only when a required detail falls outside the snippet. Use `--preview full` to expand context when needed.

### Freshness and index lifecycle

* Use the workspace root from cwd unless another root is required; when an explicit root is needed, pass a daemon-visible absolute `root` to `zg`.
* Read `freshness` and `background_refresh` from search results without a status preflight. Use `zg status [root] [--check-ready]` to inspect index state when needed.
* When results are `served_from_current_index`, use them when sufficient instead of waiting for the background refresh. Use `--refresh wait` when the latest workspace changes must be included.
* If the index is missing but exact or regex lookup can answer the task, use `zg query --rg <pattern> [path...]`.
* Creating, rebuilding, or dropping a persistent index requires an explicit user request or authorization; never do so silently. Use `zg index [root] [--rebuild] [--embedding <model>]`, `zg index [root] --drop --yes`.

### CLI command reference

```bash
# Hybrid retrieval (default)
zg query "theme preference persistence on startup"
zg query "plugin lifecycle" --limit 5 --preview full

# Semantic-only retrieval
zg query --vector "where user preferences are restored" --limit 5

# Ranked lexical retrieval
zg query --fts "loadTheme" -g "src/**" -t ts

# Multiple query groups with fusion
zg query --hybrid "concept" --fts "anchor" --vector "concept" --fuse

# Exhaustive managed ripgrep (no index needed)
zg query --rg -i -C 2 -g "*.ts" "dark mode" src

# Index management
zg index
zg index --embedding local/potion-code-16m-v2
zg index --rebuild --embedding local/jina-embeddings-v2-base-code
zg index --drop --yes

# File discovery options (shared)
# -g/--glob, --iglob, -t/--type, -T/--type-not, --hidden, --no-ignore, --ignore-file, --max-depth, --max-filesize, -L/--follow
```

### Result controls

* `--limit <n>` bounds each query group.
* `--preview <none|short|full>` controls snippet expansion.
* `-g/--glob`, `-t/--type` filter files during search.
* Indexed CLI results are separated by query group and preserve in-group rank; a result recalled by several groups appears under each.
