{
  config,
  pkgs,
  lib,
  ...
}:
{
  imports = [
    ./vscode
    ./vscode-remote
    ./vscode-wsl
    ./jetbrains-remote
  ];
}
