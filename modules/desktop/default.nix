attrs@{config, pkgs, lib, ...}:
{
  imports = (lib.my.listDirs {path = ./.;});
}
