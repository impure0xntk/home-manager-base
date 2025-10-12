{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.home.ai;

  ollomaModels = lib.concatLists (
    map (p: if p.name == "ollama" then p.models else [ ]) cfg.providers
  );
  hasOllamaModel = builtins.length ollomaModels > 0;
  ollomaProvider = lib.findFirst (p: p.name == "ollama") { url = ""; } cfg.providers;
in
{
  config = lib.mkIf (cfg.enable && hasOllamaModel) {
    services.ollama = {
      enable = true;
      acceleration = "cuda";
      environmentVariables =
        {
          # https://github.com/ollama/ollama/issues/8597#issuecomment-2614533288

          # Change models path
          OLLAMA_MODELS = "${config.xdg.dataHome}/ollama/models";

          HIP_VISIBLE_DEVICES = "0,1";

          OLLAMA_NUM_PARALLEL = "1";
          OLLAMA_KEEP_ALIVE = "1h";
        }
        //
        # https://blog.peddals.com/ollama-vram-fine-tune-with-kv-cache/
        (
          if lib.any (m: lib.hasInfix "gemma3" m.model) ollomaModels then
            {
              # For gemma3
              OLLAMA_FLUSH_ATTENTION = "0";
              OLLAMA_KV_CACHE_TYPE = "f16";
            }
          else
            {
              # General
              OLLAMA_FLUSH_ATTENTION = "1";
              OLLAMA_KV_CACHE_TYPE = "q8_0";
            }
        );
    };

    systemd.user.services.ollama-pull-models =
      let
        package = config.services.ollama.package;
        originalModelIds = map (m: m.model) (lib.filter (m: m.modelfileText == null) ollomaModels);
        customModelFiles = map (m: {
          modelId = m.model;
          modelfile = pkgs.writeText "Modelfile.${m.model}" m.modelfileText;
        }) (lib.filter (m: m.modelfileText != null) ollomaModels);

        pullScript = pkgs.writeShellScript "ollama-pull-models" (
          ''
            for model in ${lib.concatStringsSep " " originalModelIds}; do
              ${package}/bin/ollama pull "$model"
            done
          ''
          + lib.concatStringsSep "\n" (
            lib.forEach customModelFiles (m: ''
              ${package}/bin/ollama create ${m.modelId} -f ${m.modelfile}
              ${package}/bin/ollama run "${m.modelId}"
            '')
          )
        );
      in
      {
        Unit = {
          Description = "Server for local large language models";
          # depends ollama.service. see https://github.com/nix-community/home-manager/blob/master/modules/services/ollama.nix
          Requires = [ "ollama" ];
          After = [ "ollama" ];
        };

        Service.ExecStart = pullScript;

        Install = {
          WantedBy = [ "default.target" ];
        };
      };
    programs.vscode.profiles.default.userSettings = (
      lib.my.flatten "_flattenIgnore" {
        github.copilot.chat.byok.ollamaEndpoint = lib.optionalAttrs hasOllamaModel ollomaProvider.url;
      }
    );
  };
}
