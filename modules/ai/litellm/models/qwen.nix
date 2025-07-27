{ lib, ... }:
let
  commonParams = {
    temperature = 0.7;
    top_p = 0.8;
    top_k = 20;
    min_p = 0;
  };
  noThink =
    models:
    (lib.forEach models (info: {
      model = info.model;
      params = info.params // {
        extra_body.reasoning.exclude = true;
      };
    }));
in
rec {
  qwen3-think = [
    {
      model = "openrouter/qwen/qwen3-30b-a3b:free";
      params = {
        weight = 10;
      }
      // commonParams;
    }
    /*
      {
         model = "cerebras/qwen-3-32b";
         params = {
           weight = 8;
         } // commonParams;
       }
    */
  ];
  qwen3 = noThink qwen3-think;

  qwen3-big-think = [
    {
      model = "openrouter/qwen/qwen3-235b-a22b-2507:free";
      params = {
        weight = 10;
      }
      // commonParams;
    }
  ];
  qwen3-big = noThink qwen3-big-think;
  
  qwen3-coder = [
    {
      model = "openrouter/qwen/qwen3-coder:free";
      params = {
        weight = 10;
      }
      //commonParams;
    }
  ];
}
