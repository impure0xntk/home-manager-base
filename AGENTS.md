# home-manager-base - AGENTS.md

## Overview

`home-manager-base` provides Home Manager configurations for the nixos-reactor project.
It includes modules for user-level settings, applications, services, and AI/MCP integration.

This submodule is designed to be composable and machine-agnostic, allowing the same user configuration
to be applied across different machines (e.g., WSL, native Linux, Docker) with platform-specific adaptations.

## Structure

The project is organized into:

- `modules/`: Contains Home Manager modules organized by category.
    - `ai/`: AI integration, including agents, providers, prompts, and skills.
    - `cli-tools/`: Command-line interface tools and enhancements.
    - `connection/`: Network and connection-related configurations.
    - `core/`: Fundamental Home Manager settings and utilities.
    - `desktop/`: Desktop environment configurations (e.g., GNOME, KDE).
    - `documentation/`: Tools for generating and viewing documentation.
    - `editor/`: Code editor configurations (e.g., VS Code, Neovim).
    - `environments/`: Development environment setups (e.g., Python, Node.js).
    - `ide/`: Integrated Development Environment configurations.
    - `keyring/`: Secret management and keyring integrations.
    - `languages/`: Programming language-specific configurations.
    - `mcp/`: Model Context Protocol server and client configurations.
    - `misc/`: Miscellaneous utilities and tools.
    - `networks/`: Network configuration and services.
    - `platform-config/`: Platform-specific configurations (used via `myHomePlatform`).
    - `secrets-store/`: Secure secret management using SOPS and age.
    - `shell/`: Shell environment and prompt configurations.
    - `shell-prompt/`: Custom shell prompt themes and configurations.
    - `task/`: Task management and productivity tools.
    - `terminal-emulator/`: Terminal emulator configurations.
    - `vcs/`: Version control system integrations (e.g., Git, GitHub).

- `platform/`: Contains platform-specific configurations that are imported via `myHomePlatform`.
    - `native-linux.nix`: Configuration for native Linux systems.
    - `docker.nix`: Configuration for Docker containers.
    - `wsl.nix`: Configuration for Windows Subsystem for Linux.

- `flake.nix`: The flake definition for this submodule, defining inputs, outputs, and the `createModules` function.

- `tests/`: Tests for the Home Manager configuration, including flake checks and module tests.

## Development Guidelines

### Adding a New Home Manager Module

1. **Choose the appropriate category**: Place your module in the relevant subdirectory under `modules/`.
   - If the category doesn't exist, create a new directory (e.g., `modules/my-new-category/`).
   - Follow the existing naming convention (lowercase, hyphens for separation).

2. **Module format**: Each module should be a Nix file (default.nix or a file with a descriptive name) that exports an attribute set following the Home Manager module format:

   ```nix
   { config, pkgs, lib, ... }:
   {
     options = {
       # Declare options here if needed
     };
     config = {
       # Implementation here
     };
   }
   ```

3. **Using lib**: Utilize the `lib` module for common patterns:
   - `mkEnableOption`: To create a boolean enable option.
   - `mkIf`: To conditionally enable configuration.
   - `mkDefault`: To set default values that can be overridden.
   - `mkForce`: To override configuration from other modules.

4. **Options**: If your module introduces new options, declare them under `options`. Use meaningful names and descriptions.

5. **Imports**: If your module depends on other modules, add them to the `imports` list.

### Platform-Specific Configurations

- For configurations that vary by platform (e.g., WSL vs. native Linux), use the `platform/` directory.
- These are imported via `myHomePlatform` in the machine's configuration (see the root AGENTS.md for examples).

### Testing

- Write tests for your modules in the `tests/` directory.
- The test framework uses `nixpkgs.fake` and `home-manager` to evaluate modules.
- Follow the existing test patterns in `tests/modules/`.

### Nix Techniques

- Follow the Nix techniques used in the project: Flakes, home-manager modules, and option declarations.
- Prefer using `with lib;` and `with lib.types;` for clarity.
- Use `rec` for records when needed.
- Avoid global mutations; prefer functional composition.

## Critical Notes

- This submodule is used as an input in the main flake (nixos-reactor) via `home-manager-base.url = "git+file:./submodules/home-manager-base";`.
- Changes to this submodule may require updating the flake.lock in the main repository and any dependent submodules.
- The `createHomeModules` function in the main flake is used to generate machine-specific Home Manager configurations from this base.
- When adding new modules, ensure they are compatible with the `createModules` function in `flake.nix`.
- Always test your changes by running the relevant checks (see the `checks` attribute in `flake.nix`).
- For AI and MCP integration, refer to the `ai/` and `mcp/` modules as examples of complex integrations.

## AI/MCP Integration Patterns

The `ai/` module provides a pattern for integrating AI services and MCP servers:

### AI Provider Configuration

- The `ai/default.nix` module defines an `options.my.home.ai` structure that allows configuring multiple AI providers.
- Each provider can have a name, URL, and a list of models with associated roles (chat, edit, apply, autocomplete, embed, rerank).
- The module uses `submodule` to define nested options for providers and models.

### Example AI Configuration (from a machine's configuration.nix)

```nix
my.home.ai = {
  enable = true;
  localOnly = false;
  providers = [
    {
      name = "ollama";
      url = "http://localhost:11434";
      models = [
        { model = "gemma3:12b"; roles = [ "chat" "edit" "apply" ]; }
        { model = "deepseek-coder-v2:16b"; roles = [ "autocomplete" ]; }
      ];
    };
  ];
};
```

### MCP Server Configuration

- The `mcp/` module configures MCP servers and clients.
- MCP servers are defined per environment (global, vscode, documentAnalysis, etc.) using preset servers.
- The VS Code integration is handled in the `ai/default.nix` module, where MCP server access is configured for the GitHub Copilot extension.

### Example MCP Configuration

```nix
my.home.mcp.servers = {
  global = { presetServers = { devtools.enable = true; }; };
  vscode = global;
  documentAnalysis = {
    presetServers = {
      markitdown.enable = true;
      excel.enable = true;
    };
  };
};
```

## Reference

For general workflow (issue tracking, bead management, etc.), refer to the root AGENTS.md in the nixos-reactor repository.


<!-- bv-agent-instructions-v2 -->

---

## Beads Workflow Integration

This project uses [beads_rust](https://github.com/Dicklesworthstone/beads_rust) (`br`) for issue tracking and [beads_viewer](https://github.com/Dicklesworthstone/beads_viewer) (`bv`) for graph-aware triage. Issues are stored in `.beads/` and tracked in git.

### Using bv as an AI sidecar

bv is a graph-aware triage engine for Beads projects (.beads/beads.jsonl). Instead of parsing JSONL or hallucinating graph traversal, use robot flags for deterministic, dependency-aware outputs with precomputed metrics (PageRank, betweenness, critical path, cycles, HITS, eigenvector, k-core).

**Scope boundary:** bv handles *what to work on* (triage, priority, planning). `br` handles creating, modifying, and closing beads.

**CRITICAL: Use ONLY --robot-* flags. Bare bv launches an interactive TUI that blocks your session.**

#### The Workflow: Start With Triage

**`bv --robot-triage` is your single entry point.** It returns everything you need in one call:
- `quick_ref`: at-a-glance counts + top 3 picks
- `recommendations`: ranked actionable items with scores, reasons, unblock info
- `quick_wins`: low-effort high-impact items
- `blockers_to_clear`: items that unblock the most downstream work
- `project_health`: status/type/priority distributions, graph metrics
- `commands`: copy-paste shell commands for next steps

```bash
bv --robot-triage        # THE MEGA-COMMAND: start here
bv --robot-next          # Minimal: just the single top pick + claim command

# Token-optimized output (TOON) for lower LLM context usage:
bv --robot-triage --format toon
```

#### Other bv Commands

| Command | Returns |
|---------|---------|
| `--robot-plan` | Parallel execution tracks with unblocks lists |
| `--robot-priority` | Priority misalignment detection with confidence |
| `--robot-insights` | Full metrics: PageRank, betweenness, HITS, eigenvector, critical path, cycles, k-core |
| `--robot-alerts` | Stale issues, blocking cascades, priority mismatches |
| `--robot-suggest` | Hygiene: duplicates, missing deps, label suggestions, cycle breaks |
| `--robot-diff --diff-since <ref>` | Changes since ref: new/closed/modified issues |
| `--robot-graph [--graph-format=json\|dot\|mermaid]` | Dependency graph export |

#### Scoping & Filtering

```bash
bv --robot-plan --label backend              # Scope to label's subgraph
bv --robot-insights --as-of HEAD~30          # Historical point-in-time
bv --recipe actionable --robot-plan          # Pre-filter: ready to work (no blockers)
bv --recipe high-impact --robot-triage       # Pre-filter: top PageRank scores
```

### br Commands for Issue Management

```bash
br ready              # Show issues ready to work (no blockers)
br list --status=open # All open issues
br show <id>          # Full issue details with dependencies
br create --title="..." --type=task --priority=2
br update <id> --status=in_progress
br close <id> --reason="Completed"
br close <id1> <id2>  # Close multiple issues at once
br sync --flush-only  # Export DB to JSONL
```

### Workflow Pattern

1. **Triage**: Run `bv --robot-triage` to find the highest-impact actionable work
2. **Claim**: Use `br update <id> --status=in_progress`
3. **Work**: Implement the task
4. **Complete**: Use `br close <id>`
5. **Sync**: Always run `br sync --flush-only` at session end

### Key Concepts

- **Dependencies**: Issues can block other issues. `br ready` shows only unblocked work.
- **Priority**: P0=critical, P1=high, P2=medium, P3=low, P4=backlog (use numbers 0-4, not words)
- **Types**: task, bug, feature, epic, chore, docs, question
- **Blocking**: `br dep add <issue> <depends-on>` to add dependencies

### Session Protocol

```bash
git status              # Check what changed
git add <files>         # Stage code changes
br sync --flush-only    # Export beads changes to JSONL
git commit -m "..."     # Commit everything
git push                # Push to remote
```

<!-- end-bv-agent-instructions -->
