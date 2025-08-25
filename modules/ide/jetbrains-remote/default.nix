{ config, pkgs, lib, ...}:
let
  cfg = config.my.home.ide.jetbrains-remote;
in {

  options.my.home.ide.jetbrains-remote = {
    enable = lib.mkEnableOption "Whether to enable JetBrains Remote Development.";
    ides = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      description = "List of JetBrains IDEs to enable for remote development.";
    };
  };
  config = lib.mkIf cfg.enable {
    programs.jetbrains-remote = {
      enable = true;
      ides = cfg.ides;
    };
    systemd.user.services.jetbrains-remote-dev-watcher = {
      Unit = {
        Description = "Watch JetBrains RemoteDev directory for changes";
      };
      Service = {
        Type = "simple";
        ExecStart = "${pkgs.inotify-tools}/bin/inotifywait -m -r -e create,modify ~/.cache/JetBrains/RemoteDev/dist/ --format '%w%f' | while read file; do
          if echo \"$file\" | grep -q 'bin/.*\.sh$'; then
            ${pkgs.patchelf}/bin/patchelf --set-rpath \"${lib.makeLibraryPath [pkgs.zlib]}\" \"$file\"
          fi
        done";
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
