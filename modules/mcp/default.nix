# Need mcp-server-nix as overlays, NOT module.
# Because module generates json file on build, so it's not possible to use it as Nix home-manager configuration.

{
  ...
}:
{
  imports = [
    ./hub.nix
  ];
}

