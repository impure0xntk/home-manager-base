# AI Coding Agent Instructions for nixos-reactor

## Project Overview

`nixos-reactor` is a **NixOS configuration management system** with a modular architecture designed for multi-machine deployments. It uses Nix flakes, home-manager, and a sophisticated submodule pattern to manage system configurations across different machines and environments.

## Architecture

### Core Components

1. **Submodules** (4 main components):
   - `nix-lib` - Utility functions and helpers
   - `nix-pkgs` - Custom package overlays
   - `nixos-base` - Core NixOS modules
   - `home-manager-base` - Home manager configurations

2. **Machine Configurations**:
   - `machines/home-desktop/` - WSL-based desktop setup
   - `machines/office-laptop/` - Work laptop configuration
   - Each machine imports system and user modules via `createHomeModules`

3. **Profiles**:
   - `profiles/work/` - Work environment (encrypted via git-crypt)
   - `profiles/product/` - Product-specific configurations

### Key Design Patterns

**Modular Imports**: All configurations use `imports = [ ... ]` to compose modules:

```nix
imports = [
  workSystemModules
  homeSystemModules
  (createHomeModules { inherit system; machine = "home-desktop"; ... })
]
```

**Platform Abstraction**: Machines delegate to appropriate platforms:

```nix
# home-desktop uses WSL platform
imports = [ home-manager-base.myHomePlatform.wsl ];
```

## Critical Development Commands

### Daily Operations

```bash
# Apply configuration changes
makers:apply

# Execute arbitrary NixOS commands
makers nixos:exec <hostname> <command>

# Build system images
makers build <hostname> <format>

# Deploy to remote (if configured)
makers deploy <config>
```

### Submodule Management

```bash
# Update flake inputs (submodules automatically included)
nix flake update nix-lib nix-pkgs nixos-base home-manager-base

# Setup development shell
makers devshell:setup
```

### Formatting

```bash
# Format all Nix files
makers fmt-all
```

## Secrets & Security

### Encryption Strategy

- **git-crypt**: Encrypts `profiles/work/` directory
- **SOPS**: Manages secrets in `secrets-*.yaml` files
- **Age**: Encryption format for sensitive data

### Working with Encrypted Content

```bash
# Unlock git-crypt (required before viewing encrypted files)
git-crypt unlock <key-file>

# SOPS encrypted files are automatically decrypted at build time
# Reference secrets via sops.nix module:
sops.secrets."path/to/secret" = { sopsFile = ./secrets-work.yaml; };
```

**Critical**: Never commit unencrypted secrets. Always use the appropriate encryption method for the file type.

## AI & MCP Integration

### AI Configuration Pattern

The system uses a **provider abstraction** approach:

```nix
my.home.ai = {
  litellm = {
    useSopsNix = true;
    environmentFilePath = config.sops.templates.".env.llm".path;
    settings = {
      model_list = config.my.home.ai.litellm.presetModels;
    };
  };
  providers = [
    {
      name = "litellm";
      url = "http://localhost:${builtins.toString config.my.home.ai.litellm.port}";
      models = litellmAllRoleModels;
    }
  ];
};
```

### MCP Servers

MCP (Model Context Protocol) servers are configured per environment:

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

## System Configuration Patterns

### Core Module Structure

**nixos-base**: Manages system-level settings

- Boot parameters (cgroups v2, panic behavior)
- Nix daemon configuration
- Systemd service management
- Journal size limits

**home-manager-base**: Manages user-level configurations

- Shell environments
- Applications
- Services
- AI/MCP integration

### Platform-Specific Adaptations

- **WSL Integration**: Uses `home-manager-base.myHomePlatform.wsl`
- **Headless Systems**: Configurable via `config.my.system.core.headless`
- **Mutable Systems**: Controlled by `config.my.system.core.mutableSystem`

## Nix Flake Architecture

### Input Management

```nix
inputs = {
  nixpkgs.url = "github:nixos/nixpkgs/release-25.05";
  # Local submodules
  nix-lib.url = "git+file:./submodules/nix-lib";
  nixos-base.url = "git+file:./submodules/nixos-base";
  # ... other inputs
};
```

### Custom System Builder

The flake implements `mkCustomSystem` which:

- Inherits from `nixpkgs.lib`
- Applies custom overlays
- Composes modules from submodules
- Handles platform-specific configurations

## Module Development Guidelines

### Adding New System Modules

1. Place in appropriate submodule:
   - `submodules/nixos-base/modules/<category>/`
2. Follow the pattern:

   ```nix
   { lib, ... }:
   {
     options.my.system.category = { enable = lib.mkEnableOption "..."; };
     config = lib.mkIf cfg.enable { /* configuration */ };
   }
   ```

### Adding New Home Manager Modules

1. Place in `submodules/home-manager-base/modules/<category>/`
2. Use the AI module as reference for complex integrations
3. Import in machine configs via `createHomeModules`

### Adding New Machines

1. Create `machines/<machine-name>/default.nix`
2. Import appropriate system and user modules
3. Configure machine-specific settings
4. Add to flake.nix outputs if needed

## Common Patterns

### Conditional Configuration

```nix
lib.mkIf cfg.enable { /* configuration */ }
lib.mkForce value  # Override inherited value
lib.mkDefault value # Set default that can be overridden
```

### Home Module Creation

```nix
createHomeModules {
  inherit system;
  machine = "machine-name";
  extraImports = [
    ({ config, ... }: {
      imports = [ home-manager-base.myHomePlatform.wsl ];
      # machine-specific home manager config
    })
  ];
}
```

## Debugging & Development

### Building and Testing

```bash
# Test build without switching
nixos-rebuild build --flake ".?submodules=1#nixos-wsl-desktop" --impure

# Check configuration
nixos-rebuild dry-activate --flake ".?submodules=1#nixos-wsl-desktop" --impure

# View generated configuration
nixos-rebuild show-config --flake ".?submodules=1#nixos-wsl-desktop" --impure
```

### Log Analysis

```bash
# View NixOS logs
sudo journalctl -xe

# View build logs
nix build --log-format raw --show-trace .?submodules=1#nixosConfigurations.home-desktop.config.system.build.toplevel
```

## Key Files

- `flake.nix` - Main flake configuration and system builder
- `Makefile.toml` - Task automation
- `submodules/nixos-base/modules/core/default.nix` - Core system module
- `submodules/home-manager-base/modules/ai/default.nix` - AI integration example
- `machines/home-desktop/default.nix` - Desktop machine example
- `machines/office-laptop/default.nix` - Laptop machine example

## Critical Notes

1. **Always use `--impure`** when working with flake-based configurations
2. **Unlock git-crypt** before viewing encrypted files
3. **Submodules are required** - run `git submodule update --init --recursive`
4. **Impure builds needed** for WSL and development
5. **SOPS automatically decrypts** secrets at build time
6. **Test before switching** - always build/dry-run first

When making changes, focus on understanding the module composition pattern and maintain the clear separation between system-level (nixos-base) and user-level (home-manager-base) configurations.

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
