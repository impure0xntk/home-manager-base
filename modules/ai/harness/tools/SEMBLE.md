### semble

The semble MCP server registers exactly two tools: `search` and `find_related`. Call
them with the arguments listed in their schema.

- `search(query, repo, top_k, max_snippet_lines, content)` ranks code chunks against a
  natural-language query and returns file path plus exact line range, with the first ten
  lines of each hit.
- `find_related(file_path, line)` returns the chunks semantically similar to a location you
  already know, taken from a previous result.

#### Where it sits in the routing

semble is the semantic code index. It answers "which file does this" by meaning rather than
by matching, so it is the route for the questions whose answer is a location, not a line:

| Question shape | Route |
| --- | --- |
| Where is the thing that does X implemented / how does X work | semble `search` |
| What else implements this interface / who else calls this | semble `find_related` |
| Exact literal, filename, path, config key, error string, regex, hit count, path list | `zvec_grep_search` with `fts` |
| One symbol, module, package, or the file you are about to edit; callers, callees, import edges | `codegraph_explore` with an explicit `maxFiles` |

A search is not exhaustive: the engine is BM25 plus static embeddings ranked by RRF, so an
exact literal that appears in only one of many similar files is answered better by
`fts`. Conversely `fts` cannot answer "where is the retry policy implemented", because the
word `retry` may not appear in the file that implements it. Pick by the shape of the
question, not by habit, and do not run both indexes over the same question.

#### Queries

- Write the query as a description of behaviour or a symbol name ("session start index
  refresh"), not as an error message or a diff fragment.
- MUST use an English query.
- `repo` takes a local path, an https git URL, or a list of both. Several repos are indexed
  as one corpus, so when the answer may live in a sibling checkout, pass every path in a
  single call instead of calling once per repo. Result paths then carry a repo-name prefix.
- `top_k` defaults to 5. Raise it for a survey, leave it alone for a location.
- `max_snippet_lines` defaults to 10. When ten lines are not enough to confirm the hit is
  the right one, call again with `max_snippet_lines = null` for the full chunk instead of
  reading the file.
- `content` is `code`, `docs`, `config` or `all`; the server here is started with `all`, so
  pass it only to narrow a call.

#### Reading the result

Results carry their own source, so treat a sufficient snippet as already-read evidence and
read the cited file only when a required detail falls outside the snippet. Navigate straight
to the reported path and line; do not re-search the same content with another tool, and do
not grep for a string the result already showed you.

#### Freshness and index lifecycle

- The first call on a repo builds and caches its index; later calls revalidate it against
  file mtimes and reindex only what changed. The cache is keyed per repository path, so
  there is no per-repo marker directory to check before searching, and no refresh to run
  before searching.
- If a result looks stale, re-run the same `search`; the revalidation pass happens inside the
  call. Do not delete or rebuild an index directory on your own: that needs explicit user
  authorization.
- The embedding model (`minishlab/potion-code-16M-v2`) is downloaded into `HF_HOME` on first
  use, so the very first search in a session needs network. Later calls do not.
