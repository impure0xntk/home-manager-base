{ config, lib, pkgs, ... }:

{
  options.my = {
    testOption = lib.mkOption {
      type = lib.types.str;
      default = "default";
      description = "A test option for verifying home-manager option testing";
    };
  };
}
