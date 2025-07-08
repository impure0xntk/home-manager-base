{ pkgs, ... }:
let
in {
  # Set machine type for other modules.
  my.home.platform.type = "docker";

  targets.genericLinux.enable = true;
}
