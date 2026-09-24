{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.home.ai;

  # Codex copies plugin contents into its cache without following symlinks
  # (entry.file_type() skips symlinked files), so home.file symlinks install an
  # empty plugin and hooks disappear. Materialize real files via activation.
  installAgentPlugins = plugins:
    lib.concatStringsSep "\n" (
      lib.mapAttrsToList (pluginName: pkg: ''
        rm -rf "${config.home.homeDirectory}/.agents/plugins/${pluginName}"
        mkdir -p "${config.home.homeDirectory}/.agents/plugins"
        cp -r "${pkg}/." "${config.home.homeDirectory}/.agents/plugins/${pluginName}"
        chmod -R u+w "${config.home.homeDirectory}/.agents/plugins/${pluginName}"
      '') plugins
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
    home.activation.installAgentPlugins =
      lib.hm.dag.entryAfter [ "writeBoundary" ] (installAgentPlugins pluginPackages);
    my.home.ai.harness.pluginPackages = pluginPackages;
  };
}
