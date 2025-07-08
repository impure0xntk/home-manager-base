{config, pkgs, lib, ...}:
{
  home.packages = with pkgs;[
    sops
    ssh-to-age
  ];

  # Tips:
  # * When "The option `home-manager.users.john.sops.defaultSopsFile' was accessed but has no value defined. Try setting the option." occurs,
  #   It is likely that you did not specify sops.secrets."the/secret/value".
  #   Check machine configuration.
  sops.age.sshKeyPaths = [
    "${config.home.homeDirectory}/.ssh/id_${config.home.username}_sops"
  ];
}