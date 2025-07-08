{
  lib,
  ...
}:
{
  # Enable this from ${project root}/home/modules/core
  options.my.home.core = {
    nixos = {
      enable = lib.mkEnableOption "Whether to enable home manager on NixOS";
      systemConfig = lib.mkOption {
        type = lib.types.attrs;
        description = "nixos system config: config.my.system";
        default = {};
        example = {
          core = {
            mutableSystem = false;
            headless = false;
          };
        };
      };
    };
  };
}
