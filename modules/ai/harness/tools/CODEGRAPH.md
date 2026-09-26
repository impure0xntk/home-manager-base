## Codegraph

NEVER call Read or Grep to understand code structure or locate symbols.
You MUST use `codegraph_context`, `codegraph_search`, or `codegraph_callers` first.
Only call Read if codegraph explicitly returns no results AND you explain why in your response.
