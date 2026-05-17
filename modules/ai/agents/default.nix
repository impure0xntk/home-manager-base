{
  config,
  pkgs,
  lib,
  searchModelByRole,
  ...
}@args:

let
  cfg = config.my.home.ai;
in
{
  imports = [
    # CLI agent configurations
    (import ./codex.nix (args // { inherit searchModelByRole; }))
    (import ./goose-cli.nix (args // { inherit searchModelByRole; }))
    (import ./junie.nix (args // { inherit searchModelByRole; }))
    (import ./copilot-cli.nix (args // { inherit searchModelByRole; }))
    # (import ./opencode.nix (args // { inherit searchModelByRole; }))
    # Future agents can be added here:
    # (import ./agent-deck.nix (args // { inherit searchModelByRole; }))
    # (import ./other-agent.nix (args // { inherit searchModelByRole; }))
  ];

  programs.vscode.profiles.default = {
    extensions = (pkgs.nix4vscode.forVscode [
      "formulahendry.acp-client"
    ]);
    userSettings."acp.agents" = {
      "Codex CLI" = lib.optionalAttrs cfg.codex.enable { # TODO: fix
        command = "codex-acp"; # For details, see codex.nix
        args = [ ];
      };
      "Goose CLI" = lib.optionalAttrs cfg.goose.enable {
        command = "goose";
        args = [ "acp" ] ;
      };
    };
  };
}
