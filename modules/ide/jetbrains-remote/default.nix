{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.my.home.ide.jetbrains-remote;

  # Attention
  # In 2025-08-30, NixOS can no longer launch Jetbrains ide without buildFHSUserEnv.
  idesFHSWrapped = (
    map (
      ide:
      pkgs.buildFHSUserEnv rec {
        name = ide.meta.mainProgram or ide.pname;
        targetPkgs = pkgs: [ ide ];
        runScript = name;
      }
    ) cfg.ides
  );
in
{

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
      ides = idesFHSWrapped;
    };
  };
}
