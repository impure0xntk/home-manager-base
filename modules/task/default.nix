# This uses systemd user.
# If "User systemd daemon not running. Skipping reload." occured when home-manager switch,
# Add "ExecStartPre=/bin/loginctl enable-linger %i" in /lib/systemd/system/user@.service and systemctl daemon-reload+restart.
# ...? It's not working...
# see: https://serverfault.com/a/1026914
{ config, pkgs, ... }:
let
in {
  # trash management
  systemd.user = {
    startServices = true;
    timers = {
      daily = {
        Unit.Description = "daily";
        Timer = {
          OnCalendar = "daily";
          Persistent = true;
          Unit = "daily_task.target";
        };
        Install.WantedBy = ["timers.target"];
      };
      weekly = {
        Unit.Description = "weekly";
        Timer = {
          OnCalendar = "weekly";
          Persistent = true;
          Unit = "weekly_task.target";
        };
        Install.WantedBy = ["timers.target"];
      };
    };
    targets = {
      daily_task.Unit.Description = "daily task";
      weekly_task.Unit.Description = "weekly task";
    };
    services = {
      # sync-dotfiles = {
      #   Unit.Description = "sync dotfiles as chezmoi update";
      #   Service.Type = "oneshot";
      #   # for load /etc/profile.d, execute script as login shell
      #   Service.ExecStart = ''
      #     ${pkgs.bash}/bin/bash -lc "\
      #       . $HOME/.nix-profile/etc/profile.d/hm-session-vars.sh; \
      #       ${pkgs.chezmoi}/bin/chezmoi update --force"
      #   '';
      #   Install.WantedBy = ["daily_task.target"];
      # };
      trash-empty = {
        Unit.Description = "trash-empty";
        Service.Type = "oneshot";
        Service.ExecStart = "${pkgs.trash-cli}/bin/trash-empty -f 7";
        Install.WantedBy = ["daily_task.target"];
      };
    };
  };
}
