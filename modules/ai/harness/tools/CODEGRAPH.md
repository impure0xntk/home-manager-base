# AI Agent Instructions for CodeGraph

## Core Rule

You MUST use CodeGraph via CLI tools as your primary method for codebase exploration, symbol resolution, and impact analysis. Avoid running raw `grep`, `find`, or sequentially reading multiple files until you have narrowed down the targets using CodeGraph.

## Available CLI Commands

Use the local CLI via terminal execution:

- `codegraph query [options] <search>`       Search for symbols in the codebase
- `codegraph explore [options] <query...>`   Explore an area: relevant symbols' source + call paths in one shot (same output as the codegraph_explore MCP tool)
- `codegraph context [options] <task...>`    Build context for a task: relevant symbols, relationships, and code blocks
- `codegraph node [options] [name]`          One symbol's source + caller/callee trail, or read a file with line numbers + dependents (same output as the codegraph_node MCP tool)
- `codegraph files [options]`                Show project file structure from the index
- `codegraph callers [options] <symbol>`     Find all functions/methods that call a specific symbol
- `codegraph callees [options] <symbol>`     Find all functions/methods that a specific symbol calls
- `codegraph impact [options] <symbol>`      Analyze what code is affected by changing a symbol

## Strategy

1. **Never Crawl**: Instead of reading files one by one to find where a function is defined or used, call `codegraph query` or `codegraph callers` first.
2. **Context Sufficiency**: Trust the context returned by CodeGraph. It provides structure-aware code blocks in Markdown format.
3. **Double Check**: If you suspect the index is stale after modifying a file, you may trigger `codegraph sync` (though file watcher usually handles this).
