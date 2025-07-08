{ config, pkgs, lib, ... }:
let
  cfg = config.my.home.desktop.labwc;
in
{
  options.my.home.desktop.labwc.enable = lib.mkEnableOption "Whether to enable labwc";

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.labwc ];
    xsession.windowManager.command = lib.mkDefault "${pkgs.labwc}/bin/labwc";

/*     xdg.configFile."labwc/rc.xml" = {
      text = ''
        <?xml version="1.0" encoding="UTF-8"?>
        <labwc_config>
          <core>
            <gap>0</gap>
          </core>
          <theme>
            <name>Default</name>
          </theme>
        </labwc_config>
      '';
      recursive = true;
    };

    xdg.configFile."labwc/menu.xml" = {
      text = ''
        <?xml version="1.0" encoding="UTF-8"?>
        <openbox_menu>
          <menu id="root-menu" label="Labwc">
            <item label="Terminal">
              <action name="Execute">
                <command>xterm</command>
              </action>
            </item>
            <separator/>
            <item label="Exit">
              <action name="Exit"/>
            </item>
          </menu>
        </openbox_menu>
      '';
      recursive = true;
    };

    xdg.configFile."labwc/autostart" = {
      text = ''
        #!/bin/sh
        # Autostart applications
      '';
      recursive = true;
      executable = true;
    };

    xdg.configFile."labwc/themerc" = {
      text = ''
        # Theme configuration
      '';
      recursive = true;
    }; */
  };
}
