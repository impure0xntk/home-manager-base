{ config, lib, pkgs, ... }:
let
  shellAliases = {
    ".."="z ..";
    "..."="z ../..";
    "...."="z ../../..";
    "....."="z ../../../..";
    "cd"="z";
    "tar"="bsdtar";
    "unzip"="unar";
    "gunzip"="unar";
    # "delta"="batdiff";
    "NNN"="sudo -E nnn";
    "cat"="bat --paging=never --color=always";
    "ls"= lib.mkForce "eza";
    "l"= lib.mkForce "eza";
    "la"= lib.mkForce "eza -a";
    "ll"= lib.mkForce "eza -alF";
    "tree"="eza --tree";
    "eza"= lib.mkForce "eza --time-style long-iso --git";
    "less"="bat --paging=always --color=always";
    "top"="btm --basic";
    "df"="duf -only local";
    "du"="dust";
    "rm"= lib.mkForce "trash -i";
    "ps"="procs";
    "transen"="trans ja:en";
    "transja"="trans en:ja";
    "transjp"= shellAliases.transja;
    "cp"= lib.mkForce "cpz";
    "envs"="env | fzf";
    "curl" = "curlie";
    "aria2c" = "aria2c -x 16 -s 16 -k 1M";
    "download" = lib.mkForce shellAliases.aria2c;
    "dl" = lib.mkForce shellAliases.aria2c;
    "rsync" = "rsync -avz --progress";
  };

  selfMaidTool = {
    fkill = pkgs.writeShellApplication {
      # nodePackages.fkill uses npm, and npm is too slow.
      # https://issadarkthing.com/kill-process-using-fzf/
      name = "fkill";
      runtimeInputs = with pkgs; [procs bat fzf];
      text = ''
        # default to sigterm -15
        SIGNAL="-''${SIGNAL:-15}"

        if command -v procs >/dev/null 2>&1; then
          PS="procs --color always --no-header --interval=0 -- \"$*\""
          AWK="awk '{print \$1}'"
        else
          PS="ps -ef | sed 1d"
          AWK="awk '{print \$2}'"
        fi

        pid="$(eval "$PS" \
          | eval "fzf -m --header='[kill:process:$SIGNAL]' \
            --ansi --multi --info=hidden --query=\"''$*\" \
            --preview 'bat --color=always --plain --line-range=:200 /proc/{1}/status;' \
            --preview-window 'right,20%' " \
          | eval "$AWK")"

        if [ -n "$pid" ]; then
          echo "$pid" | xargs kill "$SIGNAL"
          $0 "$@"
        fi
      '';
    };
  };

in {
  home.packages = with pkgs; [
    # basic
    libarchive  # archiver
    unar        # unarchiver
    aria2       # fetcher
    fuc         # faster cp and rm
    rsync       # file transfer
    # cli tools
    delta       # alt diff. required by batdiff
    du-dust     # alt du
    duf         # alt df
    trash-cli   # remove file management
    curlie      # alt curl
    up          # stdout utility
    procs       # alt ps
    cargo-make  # taskrunner

    # not use frequently
    # sd          # alt sed
    # choose      # alt awk/cut
  ] ++ lib.attrValues selfMaidTool;
  programs = {
    bat = {
      enable = true;
      extraPackages = with pkgs.bat-extras; [ batdiff batpipe ];
      config = {
        theme = "Visual Studio Dark+";
      };
    };

    fd.enable = true;

    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    eza = {
      enable = true;
      enableBashIntegration = true;
      enableFishIntegration = true;
    };

    ripgrep.enable = true;

    zoxide = {
      enable = true;
      enableBashIntegration = true;
      enableFishIntegration = true;
    };

    fzf = rec {
      enable = true;
      enableFishIntegration = true;
      defaultCommand = "fd -H --type f";
      defaultOptions = ["--height 50%" "--layout=reverse"];
      fileWidgetCommand = defaultCommand;
      fileWidgetOptions = [
        "--preview 'bat --color=always --plain --line-range=:200 {}'"
      ];
      changeDirWidgetCommand = "fd -H --type d";
      changeDirWidgetOptions = ["--preview 'eza --tree {} | head -200'"];
      historyWidgetOptions = [];
    };

    bottom = {
      enable = true;
      settings = {
        flags = {
          avg_cpu = true;
          temperature_type = "c";
          battery = false;
        };
        processes.columns = ["pid" "name" "cpu%" "mem%" "read" "write" "user" "state" "time"];
      };
    };

    mcfly = {
      enable = true;
      enableBashIntegration = true;
      enableFishIntegration = true;
      fuzzySearchFactor = 2;
      keyScheme = "vim";
      fzf.enable = config.programs.fzf.enable;
    };

    translate-shell.enable = true;

    nnn = let
      nnnPackage = (pkgs.nnn.overrideAttrs (old: {
        nativeBuildInputs = (old.nativeBuildInputs or []) ++ [ pkgs.makeWrapper ];
        installTargets = lib.remove "install-desktop" old.installTargets;
        postInstall = (old.postInstall or "") + ''
          substituteInPlace $out/share/plugins/nuke \
            --replace-fail '"$EDITOR" ' 'eval "$EDITOR" ' # For EDITOR with options like 'code --wait'
          wrapProgram $out/bin/nnn \
            --set NNN_TRASH 1 \
            --set NNN_OPTS aABcdEix \
            --set NNN_OPENER $out/share/plugins/nuke
        '';
      })).override {
        withEmojis = true;
        extraMakeFlags = [ "O_GITSTATUS=1" "O_NAMEFIRST=1" ];
      };
    in {
      enable = true;
      package = nnnPackage;
      bookmarks = {
        t = "/tmp";
        h = "~/";
        g = "~/ghq";
      };
    };

    pet.enable = true;
  };

  programs.fish.interactiveShellInit = ''
    source ${pkgs.nnn}/share/quitcd/quitcd.fish
    procs --gen-completion-out fish | source
  '';
  programs.bash.shellAliases = shellAliases;
}
