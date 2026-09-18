{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.home.ai;

  # All default skills now use path with fetchgit expressions
  defaultSkillRepos = {
    anthropics-skills = {
      path = pkgs.fetchgit {
        url = "https://github.com/anthropics/skills.git";
        rev = "34040c9c568585f6929bedeaad110ad08f079624";
        sha256 = "sha256-tI4bTTBfI1ylltklGyiyA7pLoKXEWtrT6lrmwrpLbCw=";
      };
      includes = [
        "mcp-builder"
        "doc-coauthoring"
      ];
      excludes = [ ];
    };
    obra-superpowers = {
      path = pkgs.fetchgit {
        url = "https://github.com/obra/superpowers.git";
        rev = "b36e0829c6d0140e93cfef2ca599b1b07d4a7797";
        sha256 = "sha256-EsGNO0dULWf5Bx6bGrCv2kI2Z8aKH0kRvGiuN23wChQ=";
      };
      includes = [ ];
      excludes = [ ];
    };
    awesome-copilot = {
      path = pkgs.fetchgit {
        url = "https://github.com/github/awesome-copilot.git";
        rev = "7568a482ce2df38f8965ab5336a3220db796a4ba";
        sha256 = "sha256-wMNloxg/mKRu6yr6pj1crdk08D+wTv/kjIcjrkHriw8=";
      };
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
      path = pkgs.fetchgit {
        url = "https://github.com/sickn33/agentic-awesome-skills.git";
        rev = "46cafc80378eabd5b04b1d32ad1e96a00476df59";
        sha256 = "sha256-Rz6Fb9GTOLg+eC/C9f41yj4DcNg2X1gAyrBmYrsIECM=";
      };
      includes = [
        "debugging.*"
      ];
      excludes = [ ];
    };
    "5-whys" = {
      path = pkgs.fetchgit {
        url = "https://github.com/awesome-skills/5-whys-skill";
        rev = "353a57673f1978de4b47fb363bb065e2547fd024";
        sha256 = "sha256-Ixil5JL3Jtwl+/+Wv3hGg+yGvLBrtFdkzjCq/58gjD8=";
      };
      includes = [ ];
      excludes = [ ];
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
      fetched = value.path;
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
      description = ''Skill repositories to clone/symlink into the skills directory.'';
      type = attrsOf (submodule {
        options = {
          path = mkOption {
            type = nullOr (either str path);
            default = null;
            description = ''
              Path to the skills directory.
              Can be any Nix expression evaluating to a path:
              - fetchgit / fetchurl / fetchtar / fetchFromGitHub + subdirectory
              - Local absolute path
              - Any other path-valued expression
              When set, `package` is ignored.
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
