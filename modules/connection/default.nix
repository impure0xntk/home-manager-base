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
    matchBlocks."*" = {
      compression = true;
      forwardAgent = true;
      controlMaster = "auto";
      controlPersist = "60s";
      userKnownHostsFile = "/dev/null";
      hashKnownHosts = false;  # for host completion
      serverAliveCountMax = 3; # keepalive
      serverAliveInterval = 30; # keepalive
      extraOptions = {
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
  };
}
