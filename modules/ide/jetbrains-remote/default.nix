{ config, pkgs, lib, ...}:
let
  cfg = config.my.home.ide.jetbrains-remote;
in {

  options.my.home.ide.jetbrains-remote = {
    enable = lib.mkEnableOption "Whether to enable JetBrains Remote Development.";
    ides = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      description = "List of JetBrains IDEs to enable for remote development.";
    };
  };
  config = lib.mkIf cfg.enable {
    programs.jetbrains-remote = {
      enable = true;
      ides = cfg.ides;
    };
  };
}
