# Import vscode-server to flake as input.
# https://github.com/nix-community/nixos-vscode-server
#
{ config, pkgs, lib, ... }:
let
  cfg = config.my.home.ide.vscode-server;
  jsonFormat = pkgs.formats.json { };

  remoteConfigDir =
    {
      "vscode" = ".vscode-server";
      # "vscode-insiders" = "Code - Insiders";
      "vscodium" = ".vscodium-server";
      # "openvscode-server" = "OpenVSCode Server";
      # "windsurf" = "Windsurf";
      # "cursor" = "Cursor";
    }
    .${cfg.expectedPackage.pname};

  _configFilePath =
    name: basePath: "${basePath}/${lib.optionalString (name != "default") "profiles/${name}/"}settings.json";
  configFileMachinePath =
    name: _configFilePath name "${remoteConfigDir}/data/Machine";
in {
  options.my.home.ide.vscode-server = {
    enable = lib.mkEnableOption "Whether to enable vscode-server.";
    expectedPackage = lib.mkOption {
      type = lib.types.enum [
        pkgs.vscode
        pkgs.vscodium
      ];
      default = pkgs.vscode;
      description = "The expected package for vscode.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Tips:
    # * If use Remote-SSH between Windows and WSL, recommend to enable
    #   "localhostForwarding=True" on %HOMEPATH%/.wslconfig
    #   to use localhost.

    # For vscode with Remote-SSH and Remote-WSL.
    # This uses inotify-wait, thus do patchelf automatically.
    # Patching process is slow, so wait a minuit after downloading server.
    services.vscode-server = {
      enable = true;
      # nodejsPackage = pkgs.nodejs-slim; # not work...
      installPath = "${config.home.homeDirectory}/${remoteConfigDir}";
    };
    programs.vscode.enable = lib.mkForce (!config.services.vscode-server.enable);

    # Settings based on programs.vscode.
    # Inspire: https://github.com/nix-community/home-manager/blob/release-25.05/modules/programs/vscode.nix

    # Copy user settings, tasks, keybindings, and snippets to each profile
    # except Extensions.
    home.file = lib.mkMerge (lib.flatten [
      (lib.mapAttrsToList (n: v: [
        {
          "${configFileMachinePath n}".source = jsonFormat.generate "vscode-machine-settings" v.userSettings;
        }
      ]) config.programs.vscode.profiles)
    ]);
  };
}
