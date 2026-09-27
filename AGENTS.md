# home-manager-base - AGENTS.md

Instructions for coding agents working in this repository. Follow them exactly; they encode
invariants that are easy to break and hard to debug.

## 1. What this repository is

`home-manager-base` is a **library of Home Manager modules**. It defines no user and no machine. It
ships `myHomeModules` (everything under `modules/`) plus `myHomePlatform.<platform>`, which the
parent flake composes with real machines and profiles.

Consumer contract (never rename these outputs):

| Output | Path in the parent flake | Consumer |
| --- | --- | --- |
| `nixosModules.<system>.myHomeModules` | used as a `_module.args.imports` entry by `createHomeModules` | every NixOS machine |
| `nixosModules.<system>.myHomePlatform.<platform>` | same | `native-linux`, `docker`, `wsl` |
| `nixosModules.<system>.nixpkgs.overlays` | `overlays = [ nix-pkgs.overlays.${system} ] ++ home-manager-base.nixosModules.${system}.nixpkgs.overlays` | parent `mkCustomSystem` |
| `homeManagerModules.<system>.myHomeModules` | the same modules, self-contained | standalone Home Manager users, this repo's own checks |
| `homeManagerModules.<system>.myHomePlatform.<platform>` | same | standalone users |
| `checks.<system>.homeManagerModules` | derivation | CI |
| `checks.<system>.nixosModules` | derivation | CI |

Note the asymmetry: **inside NixOS, the overlays must be imported separately** from
`myHomeModules` because `nixpkgs` is fixed by the NixOS side. In standalone Home Manager,
`myHomeModules` already carries `nixpkgs.overlays`.

Every option lives under the **`my.home.*`** namespace. Nothing is declared at the top level of
`config`.

Supported systems: `x86_64-linux`, `aarch64-linux`. `home.stateVersion` is `"25.05"`.

## 2. Repository map

```
flake.nix                # createModules, platform attrset, overlays, checks
platform/
  native-linux/default.nix
  docker/default.nix
  wsl/default.nix       # plus wsl/alacritty/alacritty.toml and wsl/batch/*.bat
modules/
  ai/                    # the largest subsystem — see §3
  cli-tools/  connection/  core/  misc/  networks/  security/  task/
  desktop/               # i3, labwc, icewm, jwm, alacritty, chromium, bing-wallpaper, _wip/
  documentation/         # textlint presets (en, ja)
  editor/                # the VS Code profile is here (21K default.nix)
  environments/  keyring/  secrets-store/
  ide/                   # vscode (extensions), vscode-remote, vscode-wsl, jetbrains-remote
  languages/             # java, python, nix, shell, sql, markdown (each with a ruff.toml etc.)
  mcp/                   # hub.nix (mcp-remote-group-* scripts)
  platform-config/       # my.home.platform.type / .settings — see §5
  shell/  shell-prompt/  terminal-emulator/  vcs/
  _wip/                  # abandoned work; do not import from here
tests/
  flake/home-manager.nix     # checks.<system>.homeManagerModules
  flake/nixos.nix            # checks.<system>.nixosModules
  modules/**/*.nix           # extra modules injected into those two evaluations
```

`modules/` is **auto-discovered** by `createModules` through
`lib.my.listDefaultNixDirs { path = ./modules; }` — one level deep, directories only, each must
contain a `default.nix`. `modules/_wip/` is deliberately not wired in; adding a `default.nix` there
would activate it.

`createModules` always prepends `vscode-server.homeModules.default` and
`sops-nix.homeManagerModules.sops`, so every user has those available.

## 3. The `ai/` subsystem (read this before touching anything AI-related)

```
modules/ai/
  default.nix         # options.my.home.ai = { enable, providers, agents }; VS Code user settings
  agents/default.nix  # imports each agent file, threading searchModelByRole through args
  agents/codex.nix  agents/goose.nix  agents/junie.nix  agents/copilot-cli.nix
  harness/
    default.nix       # imports core, skills, prompts, tools, mcp, plugins
    core.nix          # my.home.ai.harness.{enable,skillsDir,promptsDir,pluginDir,pluginPackages}
    skills.nix        # installs SKILL.md files from git with a pinned hash
    prompts/          # the prompt catalogue + AGENTS.md installed to xdg.configFile."ai/AGENTS.md"
    tools/            # coding-agent tools: rtk, codegraph, ctx, ax, zvec-grep (zg)
      tools/*.md      # the per-tool prompt fragments concatenated into the deployed AGENTS.md
    mcp.nix  mcp-server-type.nix  plugins.nix
  subagents.nix       # planner/worker/reviewer sub-agent profiles
  orchestration/      # optional helper CLIs (currently all commented out)
  local.nix  compression.nix  NanoProxy.nix  litellm/models.nix  bot/
```

Key facts a coding agent must not get wrong:

- **Role-based model lookup.** Models are declared with `roles = [ "chat" "edit" "apply"
  "autocomplete" "embed" "rerank" ]`. `searchModelByRole` is defined in `ai/default.nix` and is
  **threaded into every agent file through the module argument set** (`args // { inherit
  searchModelByRole; }`). A new agent file must be imported that way — a plain `imports = [ ./new.nix
  ]` will not compile.
- **A new agent goes in `agents/`, is imported in `agents/default.nix`,** and gets
  `searchModelByRole` explicitly. The commented-out `agent-deck.nix` line shows the intended shape.
- **`agents/default.nix` owns every `gtr.*` git config key**, including `gtr.ai.default`, whose
  value is the `main` command of an entry in `my.home.ai.agents` — the command gtr runs, not a name
  to translate, because gtr resolves it itself (built-in adapter name, else a command on PATH). They
  go through git config rather than a repo `.gtrconfig`, which gtr treats as executable entries it
  ignores until `git gtr trust`.
- **Prompt fragments are the single source of truth for tool docs.** `harness/prompts/default.nix`
  builds the deployed `~/.config/ai/AGENTS.md` by concatenating `harness/prompts/AGENTS.md` with
  every `harness.tools.<name>.prompt`. Adding a tool means adding both the tool entry in
  `tools/default.nix` **and** its `.md` fragment — otherwise the user-level AGENTS.md silently goes
  stale.
- **Fragments and hook messages name backend tools only** (`zvec_grep_search`, `codegraph_explore`),
  never the transport that carries them. `harness/mcp.nix` multiplexes every registered backend behind
  one `mcp-compressor` process, so the tools an agent actually sees are
  `<backend>_get_tool_schema` / `<backend>_invoke_tool` — but naming that in a prompt couples the
  prompt to an implementation detail, and `--compression high` already keeps the argument names
  resident in the schema description. A tool name that the agent cannot call is worse than no name at
  all: the `PreToolUse` deny then leaves "use `rg`" as the only move, which that same hook denies.
  Verify a name against the backend's own `tools/list` before writing it into a prompt.
  The zvec-grep daemon runs its `agent` toolset, which registers `zvec_grep_search` **only** —
  `zvec_grep_rg` needs `--mcp-toolset full`, which is a daemon-wide switch every client inherits.
  See `docs/ai-harness-efficiency-plan.md` §3.1 and §3.11.
- **`plugins.nix` ships the `nixos-reactor-harness-for-all-agents` plugin** whose `hooks.json` wires
  `codegraph sync` into `SessionStart` and `codegraph prompt-hook` into `UserPromptSubmit`. The
  comment in `core.nix` explains why `plugin.json` deliberately omits `$schema` (Codex only loads
  hooks for legacy-format manifests). Do not "fix" that.
- **`mcp/` is a module, not an overlay**, because `mcp-server-nix` writes JSON at build time and
  cannot be evaluated as a Home Manager module. `hub.nix` generates
  `mcp-remote-group-<server>` wrapper scripts from `pkgs.my.mcp-server-remote`.
- **VS Code settings must be a flat nix attrset.** `ai/default.nix` uses
  `lib.my.flatten "_flattenIgnore" { … }` so that dotted keys become nested JSON, and marks keys
  that must stay literal with `_flattenIgnore = true;` (the `chat.mcp.discovery.enabled` block).
  Adding a VS Code setting that references `config.programs.vscode.userSettings` re-creates the
  infinite-recursion bug the comment above that block warns about.

## 4. Writing a module

```nix
# modules/<category>/default.nix  or  modules/<category>/<name>.nix
{ config, lib, pkgs, ... }:

let
  cfg = config.my.home.<category>;
in
{
  options.my.home.<category> = {
    enable = lib.mkEnableOption "Whether to enable <category>.";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.<tool> ];
  };
}
```

Conventions:

- **Namespace**: `my.home.*` only. `my.testOption` exists in `tests/modules/test-option.nix` purely
  as a fixture — do not use it outside tests.
- **One `enable` gate per category** with `lib.mkEnableOption`; guard `config` with `lib.mkIf`.
- Use `lib.optionals` / `lib.optionalAttrs` / `lib.mkIf` rather than inline conditionals in
  attribute position.
- `with lib; with lib.types;` inside the `options` block is the house style here (unlike
  `nixos-base`, which fully qualifies `lib.`).
- Every option gets a `description`. For nested shapes use
  `lib.types.submodule { options = { … }; }`, as in `ai/default.nix` for providers/models.
- **No secrets in values.** Reference sops paths (`config.sops.templates.…`) or
  `keyring`/`secrets-store` output. Never inline a token.
- `lib.my.*` helpers come from `nix-lib`; `pkgs.my.*` from `nix-pkgs`. A new helper means adding it
  upstream first, never re-implementing it locally.

### Platform abstraction

`my.home.platform` (`modules/platform-config/default.nix`) mirrors the `nixos-base` design: `type`
is constrained to the directory names under `platform/`, and `settings` is the per-platform option
submodule. `platform/wsl/default.nix` holds Windows-interop workarounds (`wslvpn`, `wsl-open`
aliases, `batch/init-*.bat`); keep those comments and `FIXME`s intact.

```nix
# machine config
my.home.platform = { type = "wsl"; };
imports = [ (inputs.home-manager-base.nixosModules.${system}.myHomePlatform.wsl) ];
```

## 5. Tests

`checks.<system>` has exactly two derivations, both built by
`home-manager.lib.homeManagerConfiguration`:

- `tests/flake/home-manager.nix` → `checks.<system>.homeManagerModules`. Uses
  `homeManagerModules.${system}.myHomeModules` **and** `.myHomePlatform.native-linux`.
- `tests/flake/nixos.nix` → `checks.<system>.nixosModules`. Uses
  `nixosModules.${system}.myHomeModules` and must re-declare
  `nixpkgs.overlays = self.nixosModules.${system}.nixpkgs.overlays;` because `nixpkgs` is inherited
  from the NixOS side.

To add a test, create `tests/modules/<path>/<name>.nix` and append the module to the `modules = [ … ]`
list in the corresponding `tests/flake/*.nix`. `tests/modules/ai/harness-skills.nix` (asserts a
skill lands in `xdg.configFile` with a pinned `fetchGit` hash),
`tests/modules/ide/jetbrains-remote.nix`, and `tests/modules/languages/java.nix` are the existing
examples.

**Known failure — pre-existing.** `nix flake check` here currently fails with
`error: attribute 'codegraph' missing` at `modules/ai/harness/tools/default.nix`, because this
submodule's own `flake.lock` pins a `nix-pkgs` revision that predates `pkgs/tree/codegraph/`. In the
parent repository the input is `git+file:./submodules/nix-pkgs`, so the real, current validation
is the parent's:

```bash
cd ../..
nixos-rebuild build --flake ".?submodules=1#nixosConfigurations.<machine>" --impure
nix build --no-link ".?nixosConfigurations.<machine>.config.system.build.toplevel" --impure
```

Use `nix eval` here for a fast structural check:

```bash
nix eval --no-write-lock-file .#nixosModules.x86_64-linux --apply 'm: builtins.attrNames m'
```

`--impure` is mandatory in the parent: the submodules are `git+file:` inputs, and without it Nix
evaluates a stale committed snapshot. `?submodules=1` picks up uncommitted submodule state.

## 6. Cross-repository impact

- Consumed as `git+file:./submodules/home-manager-base` by `nixos-reactor`.
- Before renaming or removing a `my.home.*` option, find every consumer:
  ```bash
  rtk grep -rn "my\.home\.<name>" ../../machines ../../home ../../profiles
  ```
- The parent defines `createHomeModules { machine, extraImports, extraSystemImports, extraOverlays }`
  and injects `home-manager-base.nixosModules.${system}.myHomeModules` through `_module.args.imports`.
  A change that breaks the `_module.args` import cycle shows up as an infinite-recursion error, not
  as a type error.
- `nix-pkgs.overlays.${system}` and `nix4vscode.overlays.forVscode` feed
  `nixosModules.<system>.nixpkgs.overlays`. Anything you add to `overlays` in `flake.nix` becomes
  visible to NixOS machines in the parent — keep the list small and intentional.
- Commit inside this submodule first, then bump the parent pointer, then review the parent
  `flake.lock` diff separately.
- `harness/prompts/AGENTS.md` and `harness/tools/*.md` are deployed to the user's home directory and
  consumed by every coding agent on the machine. Changes there are **user-visible behaviour
  changes**, not documentation edits.

## 7. Definition of done

A change is complete when:

1. The module is reachable without editing `flake.nix` (directory + `default.nix`, or imported by
   its category's `default.nix`).
2. Everything is gated behind `my.home.*` and is **off by default**.
3. `nixos-rebuild build` for at least one affected machine succeeds from the parent repo.
4. For an `ai/harness/tools` change, the matching `.md` prompt fragment is added in the same commit.
5. For an `ai/agents` change, the new file is imported in `agents/default.nix` with
   `searchModelByRole` threaded through.
6. No secret value is inlined; sops paths are used.
7. The diff touches no unrelated module and no unrelated `flake.lock` entries.
