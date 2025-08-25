# Inspire: https://github.com/bowmanjd/nix-config/raw/ec086d5cb5be0fc4bc39b12e9f1d132c60b738d5/home-manager/llm/litellm-config.yaml

{ lib, ... }:
let
  toLitellmEntry = name: cfg: {
    model_name = name;
    litellm_params = {
      model = cfg.model;
    }
    // cfg.params;
    model_info = {
      id = builtins.replaceStrings [ "/" ":" ] [ "-" "-" ] cfg.model;
    };
  };

  modelsFinal =
    modelAttrs:
    lib.flatten (
      lib.mapAttrsToList (name: defs: lib.map (def: toLitellmEntry name def) defs) modelAttrs
    );
in
modelsFinal (
  (import ./deepseek.nix { inherit lib; })
  // (import ./google.nix { inherit lib; })
  // (import ./meta.nix { inherit lib; })
  // (import ./mistralai.nix { inherit lib; })
  // (import ./moonshotai.nix { inherit lib; })
  // (import ./qwen.nix { inherit lib; })
  // (import ./openai.nix { inherit lib; })
  // (import ./others.nix { inherit lib; }) // { })

#   modelsRaw = {
#     qwen3 = [
#       {
#         model = "openrouter/qwen/qwen3-32b:free";
#         params = {
#           weight = 10;
#           extra_body = {
#             reasoning.exclude = true;
#           };
#         };
#       }
#       {
#         model = "cerebras/qwen-3-32b";
#         params = {
#           weight = 8;
#         };
#       }
#     ];
#
#     llama3 = [
#       {
#         model = "meta-llama/llama-3-70b";
#         params = {
#           weight = 9;
#         };
#       }
#     ];
#   };
# ->
# - model_name: qwen3
#   litellm_params:
#     model: openrouter/qwen/qwen3-32b:free
#     weight: 10
#     extra_body:
#       reasoning:
#         exclude: true
#   model_info:
#     id: openrouter-qwen-3-32b-free
#
# - model_name: qwen3
#   litellm_params:
#     model: cerebras/qwen-3-32b
#     weight: 8
#   model_info:
#     id: cerebras-qwen-3-32b
#
# - model_name: llama3
#   litellm_params:
#     model: meta-llama/llama-3-70b
#     weight: 9
#   model_info:
#     id: meta-llama-llama-3-70b
