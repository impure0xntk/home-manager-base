{ pkgs, lib, ... }:
let
in {
  home.packages = with pkgs; [
    openssh
    sshpass
    ssh-copy-id
    connect # for ssh proxy
  ];
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    settings."*" = {
      Compression = true;
      ForwardAgent = true;
      ControlMaster = "auto";
      ControlPersist = "60s";
      UserKnownHostsFile = "/dev/null";
      HashKnownHosts = false;  # for host completion
      ServerAliveCountMax = 3; # keepalive
      ServerAliveInterval = 30; # keepalive
      Ciphers = lib.concatStringsSep "," [
        "aes128-ctr" "aes192-ctr" "aes256-ctr"
      ];
      IgnoreUnknown = lib.concatStringsSep "," [
        "UseKeychain"
      ];
      UseKeychain = "yes";
      StrictHostKeyChecking = "no";
      LogLevel = "QUIET";
    };
  };
}
