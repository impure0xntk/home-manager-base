{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.home.ai;

  defaultSkillRepos = {
    anthropics-skills = {
      url = "https://github.com/anthropics/skills.git";
      revision = "34040c9c568585f6929bedeaad110ad08f079624";
      hash = "sha256-tI4bTTBfI1ylltklGyiyA7pLoKXEWtrT6lrmwrpLbCw=";
      includes = [
        "mcp-builder"
        "doc-coauthoring"
        "docx"
        "pdf"
        "pptx"
        "xlsx"
      ];
      excludes = [ ];
    };
    obra-superpowers = {
      url = "https://github.com/obra/superpowers.git";
      revision = "b36e0829c6d0140e93cfef2ca599b1b07d4a7797";
      hash = "sha256-EsGNO0dULWf5Bx6bGrCv2kI2Z8aKH0kRvGiuN23wChQ=";
      includes = [ ];
      excludes = [ ];
    };
    awesome-copilot = {
      url = "https://github.com/github/awesome-copilot.git";
      revision = "7568a482ce2df38f8965ab5336a3220db796a4ba";
      hash = "sha256-wMNloxg/mKRu6yr6pj1crdk08D+wTv/kjIcjrkHriw8=";
      includes = [
        "acquire-codebase-knowledge"
        "agent.*"
        "autoresearch"
        "conventional.*"
        "create-specification"
        "create-readme"
        "create-tldr-page"
      ];
      excludes = [ ];
    };
    agentic-awesome-skills =  {
      url = "https://github.com/sickn33/agentic-awesome-skills.git";
      revision = "46cafc80378eabd5b04b1d32ad1e96a00476df59";
      hash = "sha256-Rz6Fb9GTOLg+eC/C9f41yj4DcNg2X1gAyrBmYrsIECM=";
      includes = [
        "debugging.*"
      ];
    };
    "5-whys" = {
      url = "https://github.com/awesome-skills/5-whys-skill";
      revision = "353a57673f1978de4b47fb363bb065e2547fd024";
      hash = "sha256-Ixil5JL3Jtwl+/+Wv3hGg+yGvLBrtFdkzjCq/58gjD8=";
    };
  };

  matchPatterns =
    patterns: name: lib.any (pattern: builtins.match ("^" + pattern + "$") name != null) patterns;

  filterSkills =
    name: value: src:
    let
      skillsSubDir = "${src}/skills";
      isSingleSkill = builtins.pathExists "${src}/SKILL.md";
      skillNames =
        if builtins.pathExists skillsSubDir then
          builtins.attrNames (builtins.readDir skillsSubDir)
        else if isSingleSkill then
          [ name ]
        else
          builtins.attrNames (builtins.readDir src);
      filteredNames = lib.filter (
        skillName:
        let
          inIncludes = value.includes == [ ] || matchPatterns value.includes skillName;
          inExcludes = matchPatterns value.excludes skillName;
        in
        inIncludes && !inExcludes
      ) skillNames;
    in
    pkgs.runCommand "${name}-filtered" { } ''
      mkdir -p $out
      if [ -d ${src}/skills ]; then
        for skill in ${lib.concatStringsSep " " filteredNames}; do
          cp -r ${src}/skills/$skill $out/${name}-$skill 2>/dev/null || true
        done
      elif [ -f ${src}/SKILL.md ]; then
        if [ -n "${lib.concatStringsSep " " filteredNames}" ]; then
          mkdir -p $out/${name}
          cp -r ${src}/. $out/${name}/
        fi
      else
        for skill in ${lib.concatStringsSep " " filteredNames}; do
          cp -r ${src}/$skill $out/${name}-$skill 2>/dev/null || true
        done
      fi
    '';

  skillDerivationSet = lib.mapAttrs (
    name: value:
    let
      fetched = pkgs.fetchgit {
        inherit (value) url;
        rev = value.revision;
        sha256 = value.hash;
      };
    in
    filterSkills name value fetched
  ) cfg.harness.skills;

  repoSkills = lib.mapAttrs (
    repoName: repoPath:
    let
      skillDirs = builtins.attrNames (builtins.readDir repoPath);
    in
    lib.listToAttrs (
      lib.map (skillName: {
        name = skillName;
        value = {
          source = "${repoPath}/${skillName}";
        };
      }) skillDirs
    )
  ) skillDerivationSet;

  flatSkills = builtins.foldl' (acc: skills: acc // skills) { } (builtins.attrValues repoSkills);
in
{
  options.my.home.ai.harness.skills =
    with lib;
    with lib.types;
    mkOption {
      description = ''
        Skill repositories to clone/symlink into the skills directory.

        Each skill can be:
        - A git URL with an optional revision (commit SHA or tag) for pinning
        - A local absolute path (starting with /)

        **Security**: Always set `revision` to a specific commit SHA for remote
        repos. This prevents supply chain attacks where a malicious commit
        could inject harmful instructions into your AI agent's context.

        Example:
        ```nix
        my-home.ai.harness.skills.my-skill = {
          url = "https://github.com/org/skill-repo.git";
          revision = "abc123def456789...";
          hash = "sha256-...";
          includes = [ "skill-name" ];
          excludes = [ ];
        };
        ```
      '';
      type = attrsOf (submodule {
        options = {
          url = mkOption {
            type = str;
            description = "Git repository URL (https:// or git@).";
          };
          revision = mkOption {
            type = nullOr str;
            default = null;
            description = ''
              Git revision (commit SHA or tag) to pin this skill to.
              **Strongly recommended** for remote repos to prevent supply chain attacks.
              If null, the latest HEAD will be fetched (unpinned, less secure).
            '';
          };
          hash = mkOption {
            type = nullOr str;
            default = null;
            description = ''
              Optional SHA-256 hash of the fetched content for additional integrity verification.
              If provided, Nix will verify the fetched content matches this hash.
              Use `nix-prefetch-git <url> --rev <revision>` to obtain.
            '';
          };
          includes = mkOption {
            type = listOf str;
            default = [ ];
            description = "Regex patterns of skills to include.";
          };
          excludes = mkOption {
            type = listOf str;
            default = [ ];
            description = "Regex patterns of skills to exclude.";
          };
        };
      });
      default = defaultSkillRepos;
    };

  config = lib.mkIf cfg.harness.enable {
    xdg.configFile = lib.mapAttrs' (name: entry: {
      name = "ai/skills/${name}";
      value = entry;
    }) flatSkills;
  };
}
