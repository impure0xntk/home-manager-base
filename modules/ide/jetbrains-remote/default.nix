{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.my.home.ide.jetbrains-remote;

  # Attention
  # In 2025-08-30, NixOS can no longer launch Jetbrains ide without buildFHSUserEnv.
  #
  # For jetbrains-remote only because of specific mainProgram setting.
  ideFHSWrapped = ide: name:
    let
      unwrapped = ide;
    in
    (pkgs.buildFHSEnv {
      # name = ide.meta.mainProgram or ide.pname;
      inherit name;
      inherit (unwrapped) version;
      targetPkgs = pkgs: [ unwrapped ];
      runScript = name;
      passthru = {
        inherit unwrapped;
      };
    });

  # idesFHSWrapped = map (ide: ideFHSWrapped ide (ide.meta.mainProgram or ide.pname)) cfg.ides;
  idesFHSWrapped = map ideWrapped cfg.ides;
  ideWrapped = ide:
    let
      mainProgram = ide.meta.mainProgram or ide.pname;
      mainWrapped = ideFHSWrapped ide mainProgram;
      remoteDevServerWrapped = ideFHSWrapped ide "${mainProgram}-remote-dev-server";
    in ide.overrideAttrs (final: prev: {
    nativeBuildInputs = (prev.nativeBuildInputs or []) ++ [
      pkgs.coreutils
    ];

    postInstall = (prev.postInstall or "") + ''
      # makeWrapper "${lib.getExe mainWrapped}" "$out/bin/${final.meta.mainProgram}"

      MAIN_PROGRAM_PATH="$(readlink -f $out/bin/${final.meta.mainProgram})"
      REMOTE_DEV_SERVER_PATH="$(readlink -f $out/bin/${final.meta.mainProgram}-remote-dev-server)"

      mv "$MAIN_PROGRAM_PATH"{,--unwrapped}
      mv "$REMOTE_DEV_SERVER_PATH"{,--unwrapped}
      mv "$out/${final.pname}/bin/remote-dev-server"{,--unwrapped} || true
      unlink $out/bin/${final.meta.mainProgram}
      unlink $out/bin/${final.meta.mainProgram}-remote-dev-server
      ln -s "${lib.getExe mainWrapped}" "$out/bin/${final.meta.mainProgram}"
      ln -s "${lib.getExe mainWrapped}" "$MAIN_PROGRAM_PATH"
      ln -s "${lib.getExe remoteDevServerWrapped}" "$out/bin/${final.meta.mainProgram}-remote-dev-server"
      ln -s "${lib.getExe remoteDevServerWrapped}" "$REMOTE_DEV_SERVER_PATH"
      ln -s "${lib.getExe remoteDevServerWrapped}" "$out/${final.pname}/bin/remote-dev-server"
    '';
  });
in {
  options.my.home.ide.jetbrains-remote = {
    enable = lib.mkEnableOption "Whether to enable JetBrains Remote Development.";
    ides = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      description = "List of JetBrains IDEs to enable for remote development.";
    };
  };
  config = lib.mkIf cfg.enable {
    programs.jetbrains-remote = {
      enable = true;
      ides = idesFHSWrapped;
    };
    home.activation.jetBrainsRemote =
      let
        distPath = "${config.xdg.cacheHome}/JetBrains/RemoteDev/userProvidedDist";
        mkLine =
          ide:
          ''
            ${ide}/bin/${ide.meta.mainProgram}-remote-dev-server registerBackendLocationForGateway || true;
            unlink ${distPath}/${lib.replaceStrings ["-"] ["_"] ide.pname} || true
            ln -s ${ide}/${ide.pname} ${distPath}/${lib.replaceStrings ["-"] ["_"] ide.pname}
          '';
        lines = map mkLine config.programs.jetbrains-remote.ides;
        linesStr =
          ''
            rm ${distPath}/_nix_store* || true
          ''
          + lib.concatStringsSep "\n" lines;
      in
      lib.mkForce (lib.hm.dag.entryAfter [ "writeBoundary" ] linesStr);
  };
}
