{
  config,
  pkgs,
  lib,
  searchModelByRole,
  ...
}:
let
  cfg = config.my.home.ai;

  configPath = "junie/config.json";

  junie-wrapped = pkgs.symlinkJoin {
    name = "junie";
    version = pkgs.junie.version;

    paths = [
      pkgs.junie
    ];

    nativeBuildInputs = with pkgs; [
      makeWrapper
    ];

    postBuild = ''
      wrapProgram $out/bin/junie \
        --set JUNIE_CONFIG_LOCATION ${config.xdg.configFile.${configPath}.source}
    '';
  };
in
{
  options.my.home.ai.junie = {
    enable = lib.mkEnableOption "Enable Junie agent";
    extraSettings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Junie agent settings";
    };
  };
  config = lib.mkIf cfg.junie.enable {
    home.packages = [
      junie-wrapped
    ];

    xdg.configFile.${configPath}.text = builtins.toJSON (
      {
        brave = false;
        auto-update = false;
      }
      // cfg.junie.extraSettings
    );
  };
}
