{ lib, ... }:
let
  llm-4-parameters = {
    temperature = 0.6;
    top_p = 0.9;
    min_p = 0.01;
  };
in

{
  "llama-3.3" = [
    {
      model = "openrouter/meta-llama/llama-3.3-70b-instruct:free";
      params = {
        weight = 10;
      };
    }
  ];
  llama-4-maverick = [
    {
      model = "openrouter/meta-llama/llama-4-maverick:free";
      params = {
        weight = 10;
      } // llm-4-parameters;
    }
  ];
  llama-4-scout = [
    {
      model = "openrouter/meta-llama/llama-4-scout:free";
      params = {
        weight = 10;
      } // llm-4-parameters;
    }
  ];
}
