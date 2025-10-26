# Recommend to write text as markdown.

{
  config,
  pkgs,
  lib,
  ...
}:
let
  base = {
    charm = ''
      Don't hold back. Give it your all.
      Always think in English.
      For maximum efficiency, whenever you need to perform multiple independent operations, invoke all relevant tools simultaneously rather than sequentially.
    '';

    tools = {
      alternatives = ''
        You can use high performance CLI tools:
        - `ripgrep` instead of `grep`,
        - `fd` instead of `find`.
      '';
      constraints = ''
        You must ensure the following constraints:
        - No sudo: - escalate config changes
        - Cross-platform: - test on macOS & Linux
        - No secrets: - never expose keys, tokens, passwords
        - No assumptions: - don't invent files, URLs, libraries
      '';
    };

    noThink = ''
      /no_think
      Respond with facts only.
      Do not include reasoning, tags, or commentary.
      Say "Insufficient data" if unsure.
    '';

    japanese = {
      input = ''
        Input may be English, Japanese, or romaji.
        Text in quotes using Latin letters is English.
      '';
      output = ''
        Output must be Japanese only (no romaji).
      '';
    };

    security = ''
      Do not read, write and commit secrets.
    '';
  };

  mk = {
    withNoThink = prompt: ''
      ${prompt}
      ${base.noThink}
    '';

    toJapanese = prompt: ''
      ${prompt}
      ${base.japanese.input}
      ${base.japanese.output}
    '';
  };

  agent = {
    autonomous = ''
      - Default: Direct, minimal responses (≤2 lines)
      - Detail Mode: Full explanations only when user requests
      - No Fluff: Skip "I will...", "Here is...", "Based on..."
      - Execute: Don't announce, just do
      - Explain: Only for destructive operations (rm, git reset, config changes)
    '';
  };

  code = {
    coder = ''
      Follow existing conventions within each configuration file type.
      Use comments to explain complex logic or non-obvious configurations.
    '';
    generator = ''
      Return only code in plain text.
      No markdown, no ``` blocks.
      Infer most likely implementation.
      Do not ask questions.
    '';

    refactor = ''
      Optimize and refactor code using latest syntax.
      Return plain text only (no formatting or comments).
      Do not ask for input.
    '';
  };

  commit = {
    conventional = ''
      Output one-line commit message using Conventional Commits.
      Format: <type>(<scope>): <subject>
      Max 72 chars, imperative mood, no punctuation.

      Types: feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert

      Scope: lowercase identifier or omit if unclear

      Examples:
      - fix(api): handle null token
      - feat(ui): add dark mode toggle
      - refactor(auth): remove deprecated method
      - chore: update eslint config

      No body, no footer, no markdown.
    '';
  };

  shell = {
    default = ''
      ${base.charm}
      You assist in Linux/NixOS system administration (bash).
      Respond in ~100 words using markdown.
      Persist data in conversation context.
    '';
  };

  mcp = {
    usage = ''
      - WebSearch: devtools MCP to search summaries and URLs -> playwright MCP or devtools MCP to fetch and read the page
      - GitHub repository Search: devtools MCP to search repos and issues -> devtools MCP or github MCP to fetch details
    '';
  };

  # To set AGENTS.md content to default and pin it.
  # If remove this to default or config, this cannot be refer in other modules.
  presets = {
    snippets = {
      inherit
        base
        mk
        agent
        mcp
        code
        commit
        shell
        ;
    };

    instructions = {
      "AGENTS.md".text = ''
        # AGENTS.md

        ## General

        ${base.charm}

        ## Language

        ${base.japanese.input}
        ${base.japanese.output}

        ## CLI tools

        ${base.tools.alternatives}
        ${base.tools.constraints}

        ## Security

        ${base.security}

        ## Communication

        ${agent.autonomous}

        ## Specific MCP Servers Usage

        ${mcp.usage}
      '';
    };
    prompts = { };
  };
in
{
  options.my.home.ai.prompts = {
    instructions = lib.mkOption {
      type =
        with lib.types;
        attrsOf (
          submodule (
            { name, ... }:
            {
              options = {
                text = lib.mkOption {
                  type = lib.types.str;
                  description = "The instruction content as text.";
                };
                source = lib.mkOption {
                  type = lib.types.path;
                  description = "Path to a file containing the instruction content.";
                  default = "${config.xdg.configHome}/ai/instructions/${name}";
                  readOnly = true;
                };
              };
            }
          )
        );
      default = presets.instructions;
      description = "Abstract instruction prompts for AI assistants, with VS Code as base.";
    };

    prompts = lib.mkOption {
      type =
        with lib.types;
        attrsOf (
          submodule (
            { name, ... }:
            {
              options = {
                text = lib.mkOption {
                  type = lib.types.str;
                  description = "The prompt content as text.";
                };
                source = lib.mkOption {
                  type = lib.types.path;
                  description = "Path to a file containing the prompt content.";
                  default = "${config.xdg.configHome}/ai/prompts/${name}";
                  readOnly = true;
                };
              };
            }
          )
        );
      default = presets.prompts;
      description = "Specific prompts for AI assistants, with VS Code as base.";
    };

    baseDir = lib.mkOption {
      type = lib.types.path;
      description = "Base directory for prompt files.";
      default = "${config.xdg.configHome}/ai";
      readOnly = true;
    };

    snippets = lib.mkOption {
      type = with lib.types; attrsOf unspecified;
      default = { };
      description = "Legacy snippets option. Use 'instructions' and 'prompts' instead.";
    };
  };
  config = lib.mkIf (config.my.home.ai.enable) {
    xdg.configFile = lib.mkMerge [
      (lib.mapAttrs' (name: prompt: {
        name = "ai/instructions/${name}";
        value = {
          text = prompt.text;
        };
      }) config.my.home.ai.prompts.instructions)

      (lib.mapAttrs' (name: prompt: {
        name = "ai/prompts/${name}";
        value = {
          text = prompt.text;
        };
      }) config.my.home.ai.prompts.prompts)
    ];

    my.home.ai.prompts = presets;
  };
}
