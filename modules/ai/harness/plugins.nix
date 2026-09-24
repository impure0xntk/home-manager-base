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

  pluginPackages = lib.mapAttrs (
    pluginName: files:
    pkgs.runCommand pluginName {} ''
      mkdir -p "$out"

      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (
          fileName: value:
          let
            json = builtins.toJSON value;
          in
          ''
            mkdir -p "$out/$(dirname '${fileName}')"
            cat > "$out/${fileName}" <<'EOF'
            ${json}
            EOF
          ''
        )
        files
      )}
    ''
  ) cfg.harness.plugins;
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
    my.home.ai.harness.pluginPackages = pluginPackages;
  };
}
