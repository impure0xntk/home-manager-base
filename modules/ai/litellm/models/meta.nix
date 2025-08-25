{ lib, ... }:

{
  "llama-3.3" = [
    {
      model = "openrouter/meta-llama/llama-3.3-70b-instruct:free";
      params = {
        weight = 10;
      };
    }
  ];
}