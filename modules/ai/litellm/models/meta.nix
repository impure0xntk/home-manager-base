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
      };
    }
  ];
  llama-4-maverick = [
    {
      model = "groq/meta-llama/llama-4-maverick-17b-128e-instruct"; # primary
      params = { # additional params are unsupported
      };
    }
    {
      model = "openrouter/meta-llama/llama-4-maverick:free";
      params = {
      } // llm-4-parameters;
    }
  ];
  llama-4-scout = [
    {
      model = "groq/meta-llama/llama-4-scout-17b-16e-instruct"; # primary
      params = { # additional params are unsupported
      };
    }
    {
      model = "openrouter/meta-llama/llama-4-scout:free";
      params = {
      } // llm-4-parameters;
    }
  ];
}
