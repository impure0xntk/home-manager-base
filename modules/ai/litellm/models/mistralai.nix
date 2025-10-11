{ lib, ... }:
let
in
{
  devstral-small = [
    {
      model = "openrouter/mistralai/devstral-small-2505:free";
      params = {
        # https://docs.unsloth.ai/basics/tutorials-how-to-fine-tune-and-run-llms/devstral-how-to-run-and-fine-tune?utm_source=chatgpt.com
        temperature = 0.15;
        top_p = 0.95;
        top_k = 64;
        min_p = 0.01;
        max_tokens = 4096;
      };
    }
  ];
  "mistral-small-3.2" = [
    {
      model = "openrouter/mistralai/mistral-small-3.2-24b-instruct:free";
      params = {
        # https://docs.unsloth.ai/basics/tutorials-how-to-fine-tune-and-run-llms/devstral-how-to-run-and-fine-tune?utm_source=chatgpt.com
      };
    }
  ];
}
