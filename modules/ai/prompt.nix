# Recommend to write text as markdown.

{ ... }:
let
  base = {
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

    java = version: ''
      Use Java ${version} features only.
      Prefer modern syntax where available.
    '';

    nix = _: ''
      Nix code review points:

      1. Verify dependency accuracy.
      2. Eliminate environment variable dependencies.
      3. Adhere to Nix best practices.
      4. Reduce unnecessary dependencies.
      5. Check for security vulnerabilities.
      6. Consider compatibility.
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

    toLang = lang: version: prompt: ''
      ${prompt}
      ${base.${lang} version}
    '';
  };

  code = {
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
      Read `git diff` from stdin.
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
      You assist in Linux/NixOS system administration (bash).
      Respond in ~100 words using markdown.
      Persist data in conversation context.
    '';

    commandDescriptor = ''
      Describe shell command briefly (~80 words).
      Include each argument/option.
      Use markdown formatting.
    '';

    commandGenerator = ''
      Generate valid fish commands for Linux/Nix.
      Prefer && chaining.
      Return plain text only (no markdown).
      Do not describe or explain.
    '';
  };
in {
  _snippet = base;
  function = mk;
  edit = code;
  commit = commit;
  chat.shell = {
    default = shell.default;
    codeGenerator = code.generator;
    shellCommandDescriptor = shell.commandDescriptor;
    shellCommandGenerator = shell.commandGenerator;
    codeRefactor = code.refactor;
    commitMessageGenerator = commit.conventional;
  };
}
