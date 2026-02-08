{
  config,
  pkgs,
  lib,
  ...
}@args:

let
  cfg = config.my.home.ai;

  # Search for a model by role across all providers
  # Returns: { provider, url, model, roles }
  searchModelByRole =
    role:
    let
      models = builtins.concatLists (
        builtins.map (
          provider:
          builtins.filter (m: builtins.elem role m.roles) (
            builtins.map (m_: {
              inherit (provider) url;
              inherit (m_) model roles;
              provider = provider.name;
            }) provider.models
          )
        ) cfg.providers
      );
    in
    if builtins.length models > 0 then builtins.head models else null;

in
{
  imports = [
    # CLI agent configurations
    (import ./codex.nix (args // { inherit searchModelByRole; }))
    (import ./goose-cli.nix (args // { inherit searchModelByRole; }))
    # (import ./opencode.nix (args // { inherit searchModelByRole; }))
    # Future agents can be added here:
    # (import ./agent-deck.nix (args // { inherit searchModelByRole; }))
    # (import ./other-agent.nix (args // { inherit searchModelByRole; }))
  ];
}
