{ lib, config, pkgs, ... }:
let
  searchCLocale = "$(if { locale -a | grep -q C.utf8; }; then echo \"C.UTF-8\"; else echo \"C\"; fi)";
  homeDir = config.home.homeDirectory;
in {
  home.sessionPath = [
    "$XDG_BIN_HOME"
  ];
  xdg.enable = true; # XDG_CACHE_HOME XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME
  home.sessionVariables = {
    # EDITOR: default is nvim. If vscode terminal, uses code.
    EDITOR = "$(if [ -n \"$VSCODE_IPC_HOOK_CLI\" ] ; then echo \"code --wait\"; else echo \"nvim\";fi)";
    LESSHISTFILE = "-";
    # xdg User
    XDG_DESKTOP_DIR = "${homeDir}/Desktop";
    XDG_DOWNLOAD_DIR = "${homeDir}/Downloads";
    XDG_DOCUMENTS_DIR = "${homeDir}/Documents";
    XDG_MUSIC_DIR = "${homeDir}/Music";
    XDG_PICTURES_DIR = "${homeDir}/Pictures";
    XDG_VIDEOS_DIR = "${homeDir}/Videos";
    XDG_RUNTIME_DIR = "/run/user/$(id -u)";
    # xdg User unofficial
    XDG_BIN_HOME = "${homeDir}/.local/bin";

    # Locale overview: https://wiki.archlinux.org/title/locale

    # locale: master is LANG
    # (for perl error suppression)
    LANGUAGE = "$LANG";
    # LC_ALL is to overwrite locale, so DO NOT SET in home-manager. https://unix.stackexchange.com/questions/87745/what-does-lc-all-c-do
    # LC_ALL best way is C.UTF8, but in old distributions, LC_ALL:C.UTF8 not found. LC_ALL ="C";  # if not default, error.
    # Major distributions sets that all locale except LC_ALL are the same.
    # See: https://uso59634.hatenablog.jp/entry/2019/12/08/012741 https://kumakake.com/%E3%81%84%E3%81%BE%E3%81%95%E3%82%89%E3%81%AA%E3%81%8C%E3%82%89ubuntu22%E3%81%AE%E5%88%9D%E6%9C%9F%E3%82%A4%E3%83%B3%E3%82%B9%E3%83%88%E3%83%BC%E3%83%AB/

    # MEMO: previous settings is LC_ALL="C", but some applications (ex. java awt/swing) don't show UTF-8 strings.
    # Maybe C.UTF-8 is the same: https://uso59634.hatenablog.jp/entry/2019/12/08/012741
    LC_COLLATE=searchCLocale; # LC_COLLATE="C.UTF-8" is better for some languages to sort faster. https://qiita.com/methane/items/dac75ef5019b311a0f10

    # Laungae specific
    # Python: https://www.lifewithpython.com/2021/05/python-docker-env-vars.html
    PYTHONDONTWRITEBYTECODE = 1;
    PYTHONUNBUFFERED = 1;
    PYTHONUTF8 = 1;
    PYTHONIOENCODING = "UTF-8";
    PYTHONBREAKPOINT = "IPython.terminal.debugger.set_trace";
    PIP_DISABLE_PIP_VERSION_CHECK = "on";
    PIP_NO_CACHE_DIR = "off";
    # NodeJS
    NODE_USE_ENV_PROXY = lib.optionalString config.my.home.networks.proxy.enable config.my.home.networks.proxy.default; # from Node 24.3.0
  };
}
