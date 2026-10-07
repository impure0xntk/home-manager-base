# Settings based on programs.vscode.
# Inspire: https://github.com/nix-community/home-manager/blob/release-25.05/modules/programs/vscode.nix
{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.my.home.ide.zed-wsl;
  cfgZed = config.programs.zed-editor;
  jsonFormat = pkgs.formats.json { };

  configFilePath =
    basePath:
    "${basePath}/settings.json";
  # The following configs are not loaded by VS Code remote automatically.
  # Copy them to each workspace manually.
  tasksFilePath =
    basePath:
    "${basePath}/tasks.json";
  keymapFilePath =
    basePath:
    "${basePath}/keymap.json";

  genUserSettingsForZed = settings:
    (builtins.removeAttrs settings cfg.excludeSettings)
      // cfg.additionalSettings;

  copySnip = first: target: ''
    mkdir -p $(dirname ${target})
    if test -e ${target}; then
      echo "Write json ${first} to ${target}" >&2
      # mv ${target}{,.bak.$(date "+%Y%m%d%H%M%S")}
    fi
    chmod +w ${target} || true
    cp ${first} ${target}
    ! test -w && chmod +w ${target}
  '';
  mergeJsonScriptSnip = jqCmd: first: second: target: ''
    PATH=${lib.makeBinPath [ pkgs.jq ]}''${PATH:+:}$PATH
    mkdir -p $(dirname ${target})
    if test -e ${second}; then
      echo "Merge json ${first} to ${second} and write to ${target}" >&2
      ${jqCmd} ${first} ${second} > ${target}.tmp
      # if test -e ${target}; then
      #   mv ${target}{,.bak.$(date "+%Y%m%d%H%M%S")}
      # fi
      mv ${target}{.tmp,}
    else
      echo "Write json ${first} to ${target}" >&2
      chmod +w ${target} || true
      cp ${first} ${target}
    fi
    ! test -w && chmod +w ${target}
  '';

  mergeObjectJsonScriptSnip =
    first: second: target:
    mergeJsonScriptSnip "jq -S -s '.[0] * .[1]'" first second target;
  # mergeListJsonScriptSnip = first: second: target:
  #   mergeJsonScriptSnip "jq -S -s 'add'" first second target;

in
{
  options.my.home.ide.zed-wsl = {
    enable = lib.mkEnableOption "Whether to enable vscode-server.";
    expectedPackage = lib.mkPackageOption pkgs "vscode" { };
    windowsConfigDir = lib.mkOption {
      type = lib.types.path;
      default = "${config.my.home.platform.settings.windows.user.homeDirectory}/AppData/Roaming/Zed";
    };
    windowsDataDir = lib.mkOption {
      type = lib.types.path;
      default = "${config.my.home.platform.settings.windows.user.homeDirectory}/AppData/Local/Zed";
    };
    excludeSettings = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "mcp" ];
      description = "List of settings to exclude from merging.";
      example = [ "mcp" ];
    };
    additionalSettings = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Additional settings to merge.";
      example = {
        "dev.containers.executeInWSL" = true;
        "vscode-neovim.useWSL" = true;
      };
    };
  };

  config = lib.mkIf (cfg.enable && config.my.home.platform.settings.wsl.isDefaultUser) {
    assertions = [
      {
        assertion = config.my.home.platform.type == "wsl";
        message = "Import platform/wsl to enable NixOS-WSL.";
      }
    ];

    # Copy user settings, tasks, and keymaps.
    home.activation."zed-merge-settings" = lib.hm.dag.entryAfter [ "writeBoundary" ] (
      lib.concatStringsSep "\n" (
        lib.flatten [
          (mergeObjectJsonScriptSnip (jsonFormat.generate "zed-user-settings" (genUserSettingsForZed cfgZed.userSettings))
            (configFilePath cfg.windowsConfigDir)
            (configFilePath cfg.windowsConfigDir)
          )
          # delegate all tasks/keybindings/snips to Nix
          (lib.optionalString (cfgZed.userTasks != { }) (
            copySnip (jsonFormat.generate "zed-user-tasks" cfgZed.userTasks) (
              tasksFilePath cfg.windowsConfigDir
            )
          ))
          (lib.optionalString (cfgZed.userKeymaps != [ ]) (
            copySnip (jsonFormat.generate "zed-keymap" (
              map (lib.filterAttrs (_: v: v != null)) cfgZed.userKeymaps
            )) (keymapFilePath  cfg.windowsConfigDir)
          ))
        ]
      )
    );

    # Zed manages its own extensions in only Windows, so we need to copy them
    home.activation."zed-copy-extensions" = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p ${cfg.windowsDataDir}/extensions
      rm -rf ${config.xdg.dataHome}/zed/extensions/installed
      cp -rLf ${config.xdg.dataHome}/zed/extensions/installed ${cfg.windowsDataDir}/ || true
    '';
  };
}
