{ config, pkgs, lib, ... }: # should pass userList using _module.args.
let
  cfg = config.my.home.desktop.bing-wallpaper;

  currentWallpaper = "current-wallpaper";
  newWallpaper = "new-wallpaper";
  pictureDirectory = "${config.xdg.userDirs.pictures}/bing-wallpapers";

  # Bing wallpaper setting script.
  # Attention: this output does not includes shebang, so call from runtimeShell.
  script = pkgs.stdenv.mkDerivation {
    name = "bing-wallpaper-script";
    src = pkgs.fetchurl {
      url =
        "https://raw.githubusercontent.com/thejandroman/bing-wallpaper/cc7f39cbbf0af49cf03b6476b185ec3d682eb360/bing-wallpaper.sh";
      hash = "sha256-AEc2HpkOEy0hh3AgSE7SbJ3TA3MIQSFmnjin5vNl/UA=";
    };
    phases = [ "installPhase" ];
    # contains shebang at first line, so drop
    installPhase = ''
      tail -n +2 $src > $out
      '';
  };
  bingWallpaper = pkgs.writeShellApplication {
    name = "bing-wallpaper";
    runtimeInputs = [ script ] ++ (with pkgs; [ coreutils-full gnugrep gnused curl feh ]);
    text = ''
      if test -e "${pictureDirectory}/${currentWallpaper}"; then
        ${pkgs.feh}/bin/feh --bg-scale "${pictureDirectory}/${currentWallpaper}"
      fi
      rm -f ${pictureDirectory}/${newWallpaper} || true
      if ${pkgs.runtimeShell} ${script} \
        --filename "${newWallpaper}" \
        --quiet \
        --picturedir "${pictureDirectory}" \
        --ssl ; then
        ${pkgs.feh}/bin/feh --bg-scale "${pictureDirectory}/${newWallpaper}"
        rm -f ${pictureDirectory}/${currentWallpaper} || true
        mv ${pictureDirectory}/{${newWallpaper},${currentWallpaper}} || true
      fi
    '';
  };
in {
  options.my.home.desktop.bing-wallpaper.enable = lib.mkEnableOption "Whether to enable bing-wallpaper";

  config = lib.mkIf cfg.enable {
    systemd.user.services.bing-wallpaper = {
      Unit = {
        Description = "Bing wallpaper.";
      };
      Install = {
        WantedBy = [ "hm-graphical-session.target" ];
      };
      Service = {
        Type = "simple";
        ExecStart = "${bingWallpaper}/bin/bing-wallpaper";
      };
    };
  };
}
