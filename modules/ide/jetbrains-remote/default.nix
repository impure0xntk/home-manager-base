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
    nixpkgs.overlays = [
      (final: prev: {
        # https://github.com/NixOS/nixpkgs/issues/375254
        jetbrains = prev.jetbrains // {
          gateway = let
            unwrapped = prev.jetbrains.gateway;
          in prev.buildFHSEnv {
            name = "gateway";
            inherit (unwrapped) version;
        
            runScript = prev.writeScript "gateway-wrapper" ''
              unset JETBRAINS_CLIENT_JDK
              exec ${unwrapped}/bin/gateway "$@"
            '';
        
            meta = unwrapped.meta;
        
            passthru = {
              inherit unwrapped;
            };
          };
        };
      })
    ];
    programs.jetbrains-remote = {
      enable = true;
      ides = cfg.ides;
    };
    my.home.ai.mcp.servers = {
      jetbrains = {
        command = lib.getExe pkgs.mcp-server-jetbrains;
      };
    };
  };
}
