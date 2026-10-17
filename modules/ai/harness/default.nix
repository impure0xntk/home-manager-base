{ ... }:
{
  imports = [
    ./core.nix
    ./skills.nix
    ./prompts
    ./tools
    ./memory
    ./mcp.nix
    ./plugins.nix
    ./hooks.nix
    ./sandbox
  ];
}
