{ pkgs, lib, ... }:
{
  home.packages = [pkgs.jwm];
  xsession.windowManager.command = lib.mkDefault "${pkgs.jwm}/bin/jwm";
  home.file.".jwmrc".source = ./jwmrc;
}

