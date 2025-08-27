# Settings based on programs.vscode.
# Inspire: https://github.com/nix-community/home-manager/blob/release-25.05/modules/programs/vscode.nix
{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.my.home.ide.vscode-wsl;
  jsonFormat = pkgs.formats.json { };

  windowsConfigDir =
    {
      "vscode" = "Code";
      # "vscode-insiders" = "Code - Insiders";
      "vscodium" = "VSCodium";
      # "openvscode-server" = "OpenVSCode Server";
      # "windsurf" = "Windsurf";
      # "cursor" = "Cursor";
    }
    .${cfg.expectedPackage.pname};

  configFilePath =
    name: basePath:
    "${basePath}/${lib.optionalString (name != "default") "profiles/${name}/"}settings.json";
  # The following configs are not loaded by VS Code remote automatically.
  # Copy them to each workspace manually.
  tasksFilePath =
    name: basePath:
    "${basePath}/${lib.optionalString (name != "default") "profiles/${name}/"}tasks.json";
  keybindingsFilePath =
    name: basePath:
    "${basePath}/${lib.optionalString (name != "default") "profiles/${name}/"}keybindings.json";
  snippetDir =
    name: basePath: "${basePath}/${lib.optionalString (name != "default") "profiles/${name}/"}snippets";

  allProfilesExceptDefault = removeAttrs config.programs.vscode.profiles [ "default" ];

  genUserSettingsForWsl = profile:
    (builtins.removeAttrs profile.userSettings cfg.excludeSettings)
      // cfg.additionalSettings;

  copySnip = first: target: ''
    mkdir -p $(dirname ${target})
    if test -e ${target}; then
      echo "Write json ${first} to ${target}" >&2
      # mv ${target}{,.bak.$(date "+%Y%m%d%H%M%S")}
    fi
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
  options.my.home.ide.vscode-wsl = {
    enable = lib.mkEnableOption "Whether to enable vscode-server.";
    expectedPackage = lib.mkPackageOption pkgs "vscode" { };
    windowsConfigDir = lib.mkOption {
      type = lib.types.path;
      default = "${config.my.home.platform.settings.windows.user.homeDirectory}/AppData/Roaming/${windowsConfigDir}";
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

    # Tips:
    # * If use Remote-SSH between Windows and WSL, recommend to enable
    #   "localhostForwarding=True" on %HOMEPATH%/.wslconfig
    #   to use localhost.

    # Settings based on programs.vscode.
    # Inspire: https://github.com/nix-community/home-manager/blob/release-25.05/modules/programs/vscode.nix

    # Copy user settings, tasks, keybindings, and snippets to each profile, except Extensions.
    home.activation."merge-settings" = lib.hm.dag.entryAfter [ "writeBoundary" ] (
      lib.concatStringsSep "\n" (
        lib.flatten [
          (lib.mapAttrsToList (n: v: [
            (mergeObjectJsonScriptSnip (jsonFormat.generate "vscode-user-settings" (genUserSettingsForWsl v))
              (configFilePath n "${cfg.windowsConfigDir}/User")
              (configFilePath n "${cfg.windowsConfigDir}/User")
            )
            # delegate all tasks/keybindings/snips to Nix
            (lib.optionalString (v.userTasks != { }) (
              copySnip (jsonFormat.generate "vscode-user-tasks" v.userTasks) (
                tasksFilePath n "${cfg.windowsConfigDir}/User"
              )
            ))
            (lib.optionalString (v.keybindings != [ ]) (
              copySnip (jsonFormat.generate "vscode-keybindings" (
                map (lib.filterAttrs (_: v: v != null)) v.keybindings
              )) (keybindingsFilePath n "${cfg.windowsConfigDir}/User")
            ))
            (lib.optionalString (v.languageSnippets != { }) (
              lib.mapAttrsToList (
                language: snippet:
                copySnip (jsonFormat.generate "user-snippet-${language}.json" snippet) "${snippetDir n "${cfg.windowsConfigDir}/User"}/${language}.json"
              ) v.languageSnippets
            ))
            (lib.optionalString (v.globalSnippets != { }) (
              copySnip (jsonFormat.generate "user-snippet-global.code-snippets" v.globalSnippets) "${snippetDir n "${cfg.windowsConfigDir}/User"}/global.code-snippets"
            ))
          ]) config.programs.vscode.profiles)
        ]
      )
    );

    # To sync profiles
    home.activation.vscodeProfiles = lib.hm.dag.entryAfter [ "writeBoundary" ] (
      let
        modifyGlobalStorage = pkgs.writeShellScript "vscode-global-storage-modify" ''
          PATH=${lib.makeBinPath [ pkgs.jq ]}''${PATH:+:}$PATH
          file="${cfg.windowsConfigDir}/User/globalStorage/storage.json"
          file_write=""
          profiles=(${
            lib.escapeShellArgs (lib.flatten (lib.mapAttrsToList (n: v: n) allProfilesExceptDefault))
          })

          if [ -f "$file" ]; then
            existing_profiles=$(jq '.userDataProfiles // [] | map({ (.name): .location }) | add // {}' "$file")

            for profile in "''${profiles[@]}"; do
              if [[ "$(echo $existing_profiles | jq --arg profile $profile 'has ($profile)')" != "true" ]] || [[ "$(echo $existing_profiles | jq --arg profile $profile 'has ($profile)')" == "true" && "$(echo $existing_profiles | jq --arg profile $profile '.[$profile]')" != "\"$profile\"" ]]; then
                file_write="$file_write$([ "$file_write" != "" ] && echo "...")$profile"
              fi
            done
          else
            for profile in "''${profiles[@]}"; do
              file_write="$file_write$([ "$file_write" != "" ] && echo "...")$profile"
            done

            mkdir -p $(dirname "$file")
            chmod +w "$file"
            echo "{}" > "$file"
          fi

          if [ "$file_write" != "" ]; then
            chmod +w "$file"
            userDataProfiles=$(jq ".userDataProfiles += $(echo $file_write | jq -R 'split("...") | map({ name: ., location: . })')" "$file")
            echo $userDataProfiles > "$file"
          fi
        '';
      in
      modifyGlobalStorage.outPath
    );
  };
}
