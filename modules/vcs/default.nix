{ config, lib, pkgs, ... }:
let
  cfgProxy = config.my.home.networks.proxy;

  gitGraphCommand = [
    "git-graph"
    "--no-pager" "--color always" "--style round"
    ];
  gitGraphLogShort = lib.concatStringsSep " " (gitGraphCommand
    ++ ["--format" ''"%h %as %an%d%n%s"'']);
  gitGraphLogOneline = lib.concatStringsSep " " (gitGraphCommand
    ++ ["--format" ''"%h %as%d %s"'']);

  shellAliases = {
    "g"="git";
    "ga"="git add";
    "gb"="git branch";
    "gc"="git commit";
    "gcfg"="git config";
    "gco"="git checkout";
    "gd"="git diff";
    "gf"="git fetch";
    "gfix"="git commit --amend --no-edit";
    "gp"="git push";
    "gqp"="git add . && git commit -m fix && git push";
    "gs"="git status";
    "gst"="git status";

    "lg"="lazygit";
    "gr"="cd $(git-root)"; # git-root is defined by utility.nix

    "git-graph" = gitGraphLogOneline
      + "| bat --paging=always --color=always --style=plain";
    "gg" = shellAliases.git-graph;
  };

in {
  home.packages = with pkgs; [
    ghq
    git-crypt
    commitizen
    git-graph
  ];
  # user/email in home-manager/profiles/*.nix
  programs.git = {
    enable = true;
    settings = rec {
      http.proxy = lib.optionalString cfgProxy.enable cfgProxy.default;
      https.proxy = http.proxy;
      # merge settings
      merge.ff = false;
      pull.ff = "only";

      log = {
        decorate = "short";
        date = "iso";
      };
      color.ui = "auto";
      core = {
        autocrlf = false;
      };
      add.interactive.useBuiltin = false;
      delta = {
        navigate = true;
        side-by-side = true;
      };
      merge.conflictstyle = "diff3";
      diff = {
        indentHeuristic = true;
        colorMoved = "default";
      };
      submodule.recurse = true;
      alias = {
        graph = "log --graph --oneline --date-order --pretty=\"%C(yellow)%h%Creset %C(cyan)%ad%Creset %Cgreen%d%Creset%s\"";
      };
      ghq = {
        root = "~/ghq";
      };
    };
  };

  programs.delta = {
    enable = true;
    enableGitIntegration = true;
  };

  programs.lazygit = {
    enable = true;
    settings = {
      git = {
        pagers = [{
          colorArg = "always";
          pager = "${pkgs.delta}/bin/delta --dark --paging=never";
        }];
        allBranchesLogCmds = [ gitGraphLogOneline ];
        branchLogCmd = gitGraphLogShort;
      };
      customCommands = [
        {
          key = "C";
          command = "cz commit";
          description = "commit with commitizen";
          context = "files";
          loadingText = "opening commitizen commit tool";
          output = "terminal";
        }
      ];
    };
  };

  programs.git-worktree-switcher = {
    enable = true;
    enableFishIntegration = true;
  };

  programs.bash.shellAliases = shellAliases;
}
