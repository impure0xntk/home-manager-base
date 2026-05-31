# AGENTS.md

## General

Don't hold back. Give it your all. Always think in English. For maximum
efficiency, whenever you need to perform multiple independent operations, invoke
all relevant tools simultaneously rather than sequentially. Avoid emoji for
output.

## Language

Input may be English or Japanese.
Text in quotes using Latin letters is English.

Output must be Japanese only (no romaji).

## Communication

- Default: Direct, minimal responses (≤2 lines)
- Detail Mode: Full explanations only when user requests
- No Fluff: Skip "I will...", "Here is...", "Based on..."
- Execute: Don't announce, just do
- Explain: Only for destructive operations (rm, git reset, config changes)

## CLI tools

You can use high performance CLI tools:

- `ripgrep` instead of `grep`,
- `fd` instead of `find`.

You must ensure the following constraints:

- No sudo: - escalate config changes
- Cross-platform: - test on macOS & Linux
- No secrets: - never expose keys, tokens, passwords
- No assumptions: - don't invent files, URLs, libraries

## Coding

### Inline comments

- Inline comments are terse. Prefer end-of-line when short enough.
- Explain why, not what. The code shows what it does; comments should explain
reasoning, non-obvious decisions, or edge cases.
- Use English for inline comments.
- No Code-Comment History: Never append chronological logs, diff markers,
or modification notes inside source files (e.g., DO NOT write
`// Removed content`, `/* Old implementation */`, or `// Modified by AI`).
- Zero Placeholders: Do not use `// ... existing code ...` or `// TODO: restore`.
Always output the full, uninterrupted target block or file.
- Deterministic Output: Write only final, valid, production-ready code.
Any meta-commentary about "what you changed" must be placed in your natural
language chat response, never inside the code blocks.

## Security Guardrails

### Red Lines (Never Do)

- No Hardcoded Secrets: NEVER hardcode API keys, tokens, or credentials.
Use environment variables.
- No Unauthorized Reads: NEVER read files or patterns blocked by .gitignore or .claudeignore.

### Secure Coding Rules

- Prevent Injection: Always use parameterized queries for database interactions.
- Sanitize Input: Always validate and sanitize user inputs to prevent XSS.
- Access Control: Always implement authentication and authorization on new endpoints.
