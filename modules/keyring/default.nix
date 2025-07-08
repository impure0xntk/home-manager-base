{ pkgs, config, lib, home, ... }:
let
  passWithNoX = pkgs.pass.override {
    x11Support = false;
  };
  gitCredentialManager = if config.xsession.enable
    then pkgs.git-credential-manager
    else pkgs.git-credential-manager.override { pass = passWithNoX; withLibsecretSupport = false;};
  gitCredentialStore = if config.xsession.enable
    then "secretservice"
    else "cache";
in {
  home.packages = [
    gitCredentialManager
  ];
  programs.gh = {
    enable = true;
    gitCredentialHelper.enable = true;
    settings = {
      git_protocol = "https";
      editor = "";
      prompt = "enabled";
      pager = "";
      aliases = {
        co = "pr checkout";
      };
      http_unix_socket = "";
      browser = "";
    };
  };
  programs.git.extraConfig.credential = {
    credentialStore = gitCredentialStore;
    helper = "${gitCredentialManager}/bin/git-credential-manager";
  };
  # gpg-agent: boot sequence is shell.nix, and systemd.
  programs.gpg.enable = true;
  services.gpg-agent = {
    enable = true;
    enableSshSupport = true;
    enableBashIntegration = true;
    enableFishIntegration = true;
    grabKeyboardAndMouse = false;  # "gpg-agent.conf:1: invalid option" workaround
    pinentry.package = lib.mkDefault pkgs.pinentry-curses;
  };
  programs.fish.interactiveShellInit = ''
    # boot gpg-agent
    if command -v gpg-agent > /dev/null 2>&1
        # gpgconf --launch gpg-agent # for v2.1.9 or older
        if not command pgrep -x gpg-agent > /dev/null 2>&1
            begin
              gpg-agent -q --daemon 2>&1 || true
            end | grep -v "gpg-agent is already running" || true
        end
    end
  '';
}
