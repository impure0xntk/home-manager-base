{ config, pkgs, lib, ... }:
let
  cfg = config.my.home.platform;
  cfgVscodeServer = config.my.home.ide.vscode-server;

  windowsUserBinDir = "${cfg.settings.windows.user.homeDirectory}/bin";

  shellAliases = {
    "open"="wsl-open";
    "xdg-open"="wsl-open";

    # delegate clipboard management to fish-clipboard-*.
    #
    # "pbcopy"="clip.exe";
    # "pbpaste"="powershell.exe -Command Get-Clipboard";
  };

  scripts = {
    wslvpn = pkgs.writeShellApplication {
      name = "wslvpn";
      excludeShellChecks = ["SC2016"];
      text =
      let
        # Fix resolv.conf: using host dns settings.
        # https://gist.github.com/coltenkrauter/608cfe02319ce60facd76373249b8ca6?permalink_comment_id=4855200#gistcomment-4855200
        # From NixOS 24.05, must use the following sudo
        sudo = if config.my.home.core.nixos.enable
          then "/run/wrappers/bin/sudo"
          else "sudo";
      in ''
        # Fix the host "Cisco AnyConnect" network metric.
        powershell.exe Start-Process -FilePath "$(wslpath -w "${windowsUserBinDir}/set-vpn-network-metric.bat")" -Wait

        # Remove old nameservers.
        ${sudo} sed -i.bak '/nameserver/d' /etc/resolv.conf
        # Add host nameservers.
        powershell.exe -Command '(Get-DnsClientServerAddress -AddressFamily IPv4).ServerAddresses | ForEach-Object { "nameserver $_" }' | tr -d '\r' \
          | ${sudo} tee -a /etc/resolv.conf > /dev/null
      '';
    };
  };
  windowsScripts = [
    (lib.my.writeBatApplicationAttr {
      # Windows ssh using wsl. This uses from vscode.
      # This must ssh using nix-profile("not" ${pkgs.openssh}/bin/ssh) because vscode probably needs ssh-agent on nix.
      # https://github.com/microsoft/vscode-remote-release/issues/937#issuecomment-1563546978
      # if fails on wsl, see https://github.com/microsoft/vscode-remote-release/issues/937#issuecomment-1684491995
      #
      # VSCode: add "remote.SSH.path": "C:/Users/%USER%/bin/ssh-using-wsl.bat"" to settings.json
      # TODO: refine ssh binary path.
      name = "ssh-using-wsl.bat";
      text =
      let sshPath = if config.my.home.core.nixos.enable
        then "/etc/profiles/per-user/${config.home.username}/bin/ssh"
        else "${config.home.homeDirectory}/.nix-profile/bin/ssh";
      in ''
        set v_params=%*
        set v_params=%v_params:\=/%
        set v_params=%v_params:c:=/mnt/c%
        set v_params=%v_params:"=\"%
        for /f "delims=" %%a in ('powershell -Command "& {'%v_params%' -replace '\/\/wsl\$\/[^\/]*','''}"') do set "v_params=%%a"
        C:\Windows\system32\wsl.exe ${sshPath} -tt -Y %v_params%
      '';
    })
    (lib.my.writeBatApplicationAttr {
      name = "reset-windows-network.bat";
      privilege = true;
      text = ''
        netsh winsock reset
        netsh int ip reset all
        netsh winhttp reset proxy
        ipconfig /flushdns
      '';
    })
    (lib.my.writeBatApplicationAttr {
      name = "set-vpn-network-metric.bat";
      privilege = true;
      text = ''
        powershell -command "Get-NetAdapter | Where-Object {$_.InterfaceDescription -Match \"Cisco AnyConnect\"} | Set-NetIPInterface -InterfaceMetric 6000"
      '';
    })
    (lib.my.writeBatApplicationAttr {
      name = "init-registry.bat";
      text = builtins.readFile ./batch/init-registry.bat;
    })
    (lib.my.writeBatApplicationAttr {
      name = "init-filesystem.bat";
      text = builtins.readFile ./batch/init-filesystem.bat;
    })
    (lib.my.writeNoWindowBatApplicationAttr {
      name = "avoid-screensaver.vbs";
      command = "avoid-screensaver.ps1.bat"; # this creates by the below "writePowershellApplicationAttrs" that has name "avoid-screensaver.ps1"
    })
  ] ++ lib.my.writePowershellApplicationAttrs {
      name = "avoid-screensaver.ps1";
      pause = true;
      generateBatFile = true;
      text = ''
$Signature = @'
  [DllImport("user32.dll")]
  public static extern void mouse_event(long dwFlags, long dx, long dy, long cButtons, long dwExtraInfo);
'@
$MouseEvent = Add-Type -MemberDefinition $Signature -Name "Win32MouseEvent" -Namespace Win32Functions -PassThru

echo "avoid screensaver started."
echo "Press [Ctrl+C] to exit."
while ($true) {
  Start-Sleep -s 240
  $MouseEvent::mouse_event(1, 0, 0, 0, 0)
}
      '';
  };
in {
  options.my.home.platform.settings = {
    wsl.isDefaultUser = lib.mkEnableOption "Default user for WSL.";
    windows = {
      user = {
        name = lib.mkOption {
          type = lib.types.str;
          description = ''
            The user name for Windows.
            This is used to create a symbolic link to the Windows file system.
          '';
        };
        homeDirectory = lib.mkOption {
          type = lib.types.str;
          description = ''
            The home directory for Windows.
            This is used to create a symbolic link to the Windows file system.
          '';
          default = "/mnt/c/Users/" + cfg.settings.windows.user.name;
        };
        syncIdeSettings = lib.mkEnableOption "Whether to sync WSL IDE settings to windows.";
      };
    };
  };
  ####
  # wsl specific
  ####
  # systemd --user
  #  default behavior doesn't work systemd user because /run/user/UID/bus doesn't create.
  #  workaround: boot wsl with, "wsl -u root -- su <username>"
  #  see: https://github.com/microsoft/WSL/issues/8842#issuecomment-1332020835
  ####
  config = {
    # Set platform type for other modules.
    my.home.platform.type = "wsl";

    targets.genericLinux.enable = true;
    home.sessionVariables.WIN_USERNAME = cfg.settings.windows.user.name;
    home.sessionPath = [
      "/mnt/c/windows/System32/WindowsPowerShell/v1.0/" # for powershell
    ];
    home.packages = (with pkgs; [
      wsl-open # is faster than wslview on wslu
      wslu

      wslsudo
    ]) ++ lib.attrValues scripts;
    programs.bash.shellAliases = shellAliases;

    # gpg-agent pinentry
    services.gpg-agent.pinentry.package = lib.mkForce pkgs.pinentry-wsl-ps1;

    home.file = {
      # for gh(requires xdg-open in PATH)
      ".local/bin/xdg-open".source = config.lib.file.mkOutOfStoreSymlink "${pkgs.wsl-open}/bin/wsl-open";
    };
    # Copy bat/ps1 scripts to Windows.
    # Only default user can use this. Because of permissions.
    xdg.dataFile = lib.mkIf cfg.settings.wsl.isDefaultUser (lib.my.createSynchronizedWindowsBinFile windowsScripts);

    programs.pet.snippets = [
      {
        command = ''${config.my.home.platform.settings.windows.user.homeDirectory}'';
        description = "Windows home directory";
        tag = ["WSL" "windows" "path"];
      }
    ];
    programs.nnn.bookmarks = let
      winHome = config.my.home.platform.settings.windows.user.homeDirectory;
    in {
      w = winHome;
      d = winHome + "/AppData/Local/Temp/_daily_operation";
    };

    programs.vscode.profiles.default.userSettings = {
      "dev.containers.executeInWSL" = true;
      "vscode-neovim.useWSL" = true;

      "update.enableWindowsBackgroundUpdates" = false;

      # Set ssh-using-wsl.bat path to "remote.SSH.path"
      # to use wsl .ssh/config
    };
    
    # The following settings works only wsl default user.
    my.home.ide.vscode-wsl.additionalSettings = lib.optionalAttrs cfg.settings.wsl.isDefaultUser {
      "remote.SSH.path" =
        "C:/Users/${config.my.home.platform.settings.windows.user.name}/bin/ssh-using-wsl.bat";
    };

    home.activation.syncVscodeSettings =
      let
        dirName = if cfgVscodeServer.expectedPackage == pkgs.vscode then "Code" else "VSCodium";
        basePath = "${cfg.settings.windows.user.homeDirectory}/AppData/Roaming/${dirName}";
      in lib.mkIf (cfg.settings.windows.user.syncIdeSettings
        && cfg.settings.wsl.isDefaultUser)
        (lib.hm.dag.entryAfter [cfgVscodeServer.activationScriptDagName] ''
        test -e ${basePath}/User && mv ${basePath}/User{,.bak.$(date "+%Y%m%d%H%M%S")}
        cp -rL ${cfgVscodeServer.userDir} ${basePath}
      '');
    };
}
