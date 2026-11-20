# jcode patches

Local patches applied to `pkgs.jcode` so this machine can run jcode the way it
wants it. They are wired in one place only,
[`modules/ai/agents/jcode.nix`](../../agents/jcode.nix):

```nix
jcodePkg = pkgs.jcode.overrideAttrs (old: {
  patches = (old.patches or [ ])
    ++ [
      ../patches/jcode/ui-toggles.patch
      ../patches/jcode/model-override.patch
      ../patches/jcode/system-prompt.patch
    ];
});
```

`pkgs.jcode` itself is untouched, so the attribute name, the version, the
source hash and the vendor hash stay owned by `llm-agents.nix`, and every other
consumer of `pkgs.jcode` on this machine keeps the unpatched build. `patches`
is a `mkDerivation` attribute consumed during `patchPhase`, so the vendor
closure -- and therefore `cargoHash` -- is unaffected by anything in this
directory. Only source files change; the vendor closure is not touched.

## Target version

All three patches are written against one exact upstream tree, and that tree is
the GitHub tarball of a release tag, not `master`:

| | |
| --- | --- |
| jcode version | `1.0.0` |
| tag | `v1.0.0` |
| `src.outputHash` | `sha256-Iui5yqSFc+7Jc+rJAorGz0mcrPTWnRnG0BZdDKDVnQI=` |
| `cargoHash` | `sha256-jqecPMahg6sTN50ZfQmPwwo46R2KWEYwkLPcvJLT5cs=` |
| `src.url` | `https://github.com/1jehuang/jcode/archive/refs/tags/v1.0.0.tar.gz` |
| package source | `numtide/llm-agents.nix`, `packages/jcode/package.nix` |
| `llm-agents` pin | `3e6e622935b31f805b3ef893d71b97c1469965e1` |

### Drift worth knowing at 1.0.0

The shared header builder and input composer both gained new responsibilities, so
those gates must cover the actual render paths rather than the older helpers:

- `build_header_sections` is still the shared render entry point for the
  persistent and secondary headers. The gate belongs before its replay guard,
  so both sections stay hidden in normal rendering and the test-only wrappers
  remain untouched.
- `prompt_number_label` is used by the live composer width calculation,
  wrapped-input preview and status renderer. Keep them on one helper so hidden
  numbers do not leave reserved columns or reappear in one rendering path.
- `initial_header_pad_top` takes `header_lines: usize`; the empty-header guard
  collapses the vertical centering gap when the rendered header height is zero,
  not when the config flag is off. This remains valid if any other path
  produces an empty header.

All other gates still apply to the same behavior as the preceding release:
onboarding is suppressed on both startup and after-login paths, the welcome
screen and starter cards have independent gates, and the info widget can still
be toggled back on.

Every hunk is re-derived against the 1.0.0 tree, so `patch -p1` reports no
offsets and no fuzz. Fuzz on a later version means a gate moved and the hunk
needs re-deriving, not a wider context.

Re-derive the pin after a `nix flake update`:

```bash
# from the parent repository root
rtk grep -n -A20 '^    "llm-agents": \{' flake.lock
nix eval --raw --impure --expr \
  "(builtins.getFlake \"git+file://$PWD\").inputs.llm-agents.packages.x86_64-linux.jcode.version"
```

The `git+file://` ref is what makes this work: a bare path makes Nix read the
working tree, which fails outright on an untracked socket like `.codegraph/`.

`llm-agents` exposes every package under `packages.<system>.<name>`; it has no
`legacyPackages` output. `packages/jcode/package.nix` is the only place its
`version`, `src.hash` and `cargoHash` are written down, and a version bump
there is what invalidates this directory.

The rest of the table is the same evaluation, two more attributes deep:

```bash
nix eval --impure --raw --expr \
  "(builtins.getFlake \"git+file://$PWD\").inputs.llm-agents.packages.x86_64-linux.jcode.src.outputHash"
nix eval --impure --raw --expr \
  "(builtins.getFlake \"git+file://$PWD\").inputs.llm-agents.packages.x86_64-linux.jcode.cargoHash"
```

`src.outputHash` rather than `src.hash`: `hash` is the legacy alias and reads
both variables at once, which is why it prints the single string appended to
itself. The source is a GitHub tarball, not a git fetch, so the tag's commit
object is not part of the package input and cannot be verified here.

If that `version` is no longer `1.0.0`, treat this directory as stale and
follow [Upgrading](#upgrading) before anything else. A patch that still applies
is not necessarily a patch that still means what its comment says.

## Conventions

Rules every patch here follows, and the reason each one exists:

- **Additive, behind the upstream default.** A new option defaults to whatever
  upstream already did, so applying the patch to an unconfigured install is a
  no-op. Anything else would make this directory a fork.
- **Minimal context, no `index` lines.** `patchPhase` runs GNU `patch -p1`
  against a tarball that has no `.git`, so a `git apply`-only patch is not
  enough and a full-context patch fails on unrelated drift. Small hunks keep
  independently changed sites from rejecting the whole file.
- **Comments explain why, not what.** The code already says what it does. Every
  comment added by these patches answers "why is this here", and says what
  breaks without it.
- **Configuration is the only way to switch a new key off.** The patch adds the
  key; `settings` in `jcode.nix` sets its value. A patch that hard-codes a
  preference for this machine belongs in `settings`, not here.
- **Stay out of the provider bootstrap.** The credential and profile plumbing in
  `jcode.nix` is delicate (see the `apiKeyEnvOf` comment); a patch that
  changes how providers are selected breaks that contract in a way the Nix
  side cannot see.
- **English comments**, matching the rest of the module.

## `ui-toggles.patch`

TUI chrome this machine does not want, which upstream hard-wires. Four keys are
added, each defaulting to `true`, and `jcode.nix` sets all four to `false`:

| key | default | effect when `false` |
| --- | --- | --- |
| `[features] onboarding` | `true` | drops the telemetry notice, the welcome title, the guided login walkthrough and the starter suggestion cards |
| `[display] show_header` | `true` | drops the whole header above the transcript: the `jcode` / `server:` / `client:` identity lines, the provider + model line, and the `/login to add provider` inventory |
| `[display] show_prompt_numbers` | `true` | renders a bare `> ` instead of `1> `, and reclaims the columns |
| `[display] show_info_widget` | `true` | starts with the right-hand info box empty; `Alt+I` still brings it back for the rest of the session |

Files and where each key is gated:

| file | what the hunk does |
| --- | --- |
| `crates/jcode-config-types/src/display.rs` | declares the three `DisplayConfig` fields and their `Default` arms |
| `crates/jcode-config-types/src/lib.rs` | declares `FeatureConfig::onboarding` and its `Default` arm |
| `crates/jcode-tui/src/tui/app/onboarding_flow_control.rs` | skips the guided flow on both the startup path and the after-login path |
| `crates/jcode-tui/src/tui/app/state_ui_input_helpers.rs` | gates the welcome screen and the suggestion cards |
| `crates/jcode-tui/src/tui/info_widget.rs` | seeds `WidgetsState::enabled` from the key; the `Alt+I` toggle is untouched |
| `crates/jcode-tui/src/tui/ui_header.rs` | returns both header sections empty, gated on the one function the render path calls |
| `crates/jcode-tui/src/tui/ui_input.rs` | one `prompt_number_label` helper used by the width calculation, the live composer, and the test-only idle resume composer |
| `crates/jcode-tui/src/tui/ui_input_status_rendering.rs` | the status-line composer calls the same helper, so hidden numbers do not reappear in that rendering path |
| `crates/jcode-tui/src/tui/ui_prepare.rs` | collapses the top pad when the header is empty, keyed on height rather than on the flag |

Two of these are worth knowing about when a hunk fails to apply, because both
are gates on *several* call sites rather than one: onboarding has three
independent render paths, and the suggestion cards are a fourth surface that
hiding the welcome screen alone does not remove. A version bump that adds a
fifth onboarding surface needs a new hunk, not just a re-applied one.

## `model-override.patch`

Makes `jcode --model X` work against the persistent daemon.

Upstream reads `--model` in the client, but the provider is constructed once, in
the server process, at `serve` bootstrap. The client can only pass the flag
along when it spawns the server itself, so on every launch after the first,
`jcode --model X` is dropped with a warning. The daemon is long-lived by
design, which means that is every launch in practice.

The patch splits the flag by what it actually is:

- `--model` is a per-session setting, and the client already speaks
  `Request::SetModel` to the session it attaches to -- it is the request the
  in-TUI `/model` command sends. So the client forwards it.
- `--provider` is server-wide: it is chosen once at bootstrap and every
  attached session inherits it. It still needs a restart, so the warning stays.

| file | what the hunk does |
| --- | --- |
| `src/cli/dispatch.rs` | `run_default_command` sets `JCODE_CLIENT_MODEL_OVERRIDE` when a server was already running, and narrows the restart warning to `--provider` / `--provider-profile` |
| `crates/jcode-tui/src/tui/backend.rs` | `connect_with_session` sends `Request::SetModel` after `Subscribe` and before `GetHistory` |

Why an environment variable rather than a new argument threaded through
`run_tui_client`, `App::new_for_remote_with_options` and `RemoteConnection`: the
value has to cross a crate boundary, and this codebase already carries
client-to-server launch state that way (`JCODE_RESUMING`,
`JCODE_PROVIDER_PROFILE_NAME`, `JCODE_TOOL_PROFILE`, `JCODE_SSH_REMOTE`). It
costs two files instead of five and survives more upstream churn.

Two details that are load-bearing:

- The request goes **between** `Subscribe` and `GetHistory`, so the first
  `History` already describes the requested model instead of rendering the
  server default and then correcting it.
- The override is read on **every** `connect_with_session`, not consumed once.
  That is intentional: the flag describes this launch, not this connection, and
  a `/reload` or a reconnect re-execs the daemon, which reloads `config.toml`.

What this does not cover, and why:

- `--provider` and `--provider-profile`. Server-wide, as above. A provider
  switch still needs `jcode server reload` or a stop/start cycle.
- `jcode --selfdev`. That path builds its own TUI launch and never reaches
  `run_default_command`.
- `jcode ssh`. The local client there is a bridge; the remote session belongs
  to the remote machine's daemon.
- `config.toml`. This is a launch-time override, like `--model` is meant to be.
  It is not persisted, so it does not quietly rewrite the default. Making a
  model stick is `jcode provider add --set-default`, or `Ctrl+O` in the model
  picker, which is upstream behaviour and needs no patch.

Upstream references, if any of this stops being true:

- <https://github.com/1jehuang/jcode/issues/809> -- `--provider` and `--model`
  ignored by a running server. Still open; the workaround given there is the
  in-TUI `/model`, which is what the patch automates.
- <https://github.com/1jehuang/jcode/issues/608> -- model selection not
  persisted to `config.toml`. Still open, and deliberately not addressed here.
- `crates/jcode-provider-core/src/selection.rs`, `explicit_model_provider_prefix`
  -- the route prefixes (`openai-api:`, `claude:`, `bedrock:`, a named
  `<profile>:`) that make a bare `--model` able to switch provider. The patch
  reuses them, so it needs no list of its own.
- `src/cli/dispatch.rs` in the upstream tree still carries the warning this
  patch rewrites. If that text is gone upstream, the bug is fixed and the patch
  should be dropped rather than adapted.

## Verifying

The cheap checks, in the order worth running them. None of these build the
package.

```bash
# 1. Apply for real, to the tree this claims to target.
PATCHES=.../modules/ai/patches/jcode            # this directory
git clone --depth 1 --branch v1.0.0 https://github.com/1jehuang/jcode.git "$JCODE_SCRATCH_DIR/jcode"
cd "$JCODE_SCRATCH_DIR/jcode"
for p in "$PATCHES"/*.patch; do patch -p1 --forward < "$p"; done
```

Cloning needs GitHub reachable, which a fenced session often is not. The tree
the build actually patches is already local then, and it is the same bytes:

```bash
# Same tree, no network. Compare skips nothing: this is inputHash, not a cache.
mkdir -p "$JCODE_SCRATCH_DIR/jcode" && cd "$JCODE_SCRATCH_DIR/jcode"
nix build --impure --no-link '.?submodules=1#legacyPackages' # or locate the src:
nix eval --impure --expr \
  "(builtins.getFlake \"git+file://$PWD\").inputs.llm-agents.packages.x86_64-linux.jcode.src"
# then extract the printed store path, chmod -R u+w, and patch as above.
```

# 2. Do the patched files still parse, and are the hunks still formatted?
#    Step 1 has to have run: the pristine tree parses trivially.
nix shell nixpkgs#rustfmt -c rustfmt --edition 2024 --check \
  src/cli/dispatch.rs \
  crates/jcode-tui/src/tui/backend.rs \
  crates/jcode-config-types/src/display.rs \
  crates/jcode-config-types/src/lib.rs \
  crates/jcode-tui/src/tui/app/onboarding_flow_control.rs \
  crates/jcode-tui/src/tui/app/state_ui_input_helpers.rs \
  crates/jcode-tui/src/tui/info_widget.rs \
  crates/jcode-tui/src/tui/ui_header.rs \
  crates/jcode-tui/src/tui/ui_input.rs \
  crates/jcode-tui/src/tui/ui_input_status_rendering.rs \
  crates/jcode-tui/src/tui/ui_prepare.rs

# 3. Does the module still evaluate?
cd submodules/home-manager-base
nix-instantiate --parse modules/ai/agents/jcode.nix
```

A rejected hunk is the *cheap* outcome. The expensive failure is a patch that
applies cleanly and has quietly stopped doing anything, so after a version bump,
always rebuild and check the behaviour, not just the apply.

The real check is a build, and it is expensive: `aws-lc-sys` and `openssl` are
native, and the vendor closure is the whole workspace. From the parent repo:

```bash
nixos-rebuild build --flake ".?submodules=1#nixosConfigurations.<machine>" --impure
```

`--impure` is mandatory there, and `?submodules=1` picks up uncommitted
submodule state, which is what makes it the right command while iterating on a
patch.

## Upgrading

1. Bump `llm-agents` in the parent `flake.lock` and note the new jcode `version`.
2. Check the new tag for each key this directory owns:
   - the four chrome keys in `ui-toggles.patch`
   - the `server_running && explicit_provider_or_model` block in
     `src/cli/dispatch.rs` for `model-override.patch`
3. Re-apply each patch by hand rather than by context matching, so the new
   hunks are written against the code as it now reads. Get the tree with
   `git clone --depth 1 --branch <tag>`, make the edit, and regenerate:
   `git diff -U2 | grep -v '^index ' > <patch>`. Keep the comment; on a new
   version the "why" usually changes even when the "what" does not.
4. Run the three checks above.
5. Diff the new patch against the old one and read every changed line. A hunk
   that got smaller usually means a gate moved and a call site is now
   ungated.
6. Update the target version table above, and the `settings` comment in
   `agents/jcode.nix` if a new key appeared or an old one changed meaning.
7. Build from the parent repo and exercise the behaviour: launch the TUI with
   the keys set, and `jcode --model` against a running daemon.

Do not resolve a drifted hunk by adding context lines. A hunk that needs more
context has usually moved because the code around it changed meaning, and the
question to answer is whether the gate still belongs where it was -- not how to
make `patch` stop complaining.
