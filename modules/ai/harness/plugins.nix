{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.home.ai;

  pluginHomeFiles = lib.listToAttrs (
    lib.concatLists (
      lib.mapAttrsToList (
        pluginName: files:
        lib.mapAttrsToList (
          fileName: value: {
            name = ".agents/plugins/${pluginName}/${fileName}";
            value.text = builtins.toJSON value;
          }
        )
        files
      )
      config.my.home.ai.harness.plugins
    )
  );
in
{
  options.my.home.ai.harness.plugins =
    with lib;
    with lib.types;
    mkOption {
      description = ''Plugins'';
      type = attrs;
      default = defaultPlugins;
    };

  config = lib.mkIf cfg.harness.enable {
    # Agent Plugins common path
    home.file = pluginHomeFiles;
  };
}
