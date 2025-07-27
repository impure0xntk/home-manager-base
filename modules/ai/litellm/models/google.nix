# TODO: add gemini api
{ lib, ... }:
let
in
{
  gemma-3 =
    let
      params = {
        # https://docs.unsloth.ai/basics/tutorials-how-to-fine-tune-and-run-llms/gemma-3-how-to-run-and-fine-tune
        temperature = 1.0;
        top_p = 0.95;
        top_k = 64;
        min_p = 0;

        max_output_tokens = 8192;
        max_input_tokens = 128000;
      };
    in
    [
      {
        model = "openrouter/google/gemma-3-27b-it:free";
        params = params // {
          weight = 10;
        };
      }
    ];
  gemma-3n =
    let
      params = {
        # https://docs.unsloth.ai/basics/tutorials-how-to-fine-tune-and-run-llms/gemma-3-how-to-run-and-fine-tune
        temperature = 1.0;
        top_p = 0.95;
        top_k = 64;
        min_p = 0;

        max_output_tokens = 8192;
        max_input_tokens = 128000;
      };
    in
    [
      {
        model = "openrouter/google/gemma-3n-e4b-it:fre";
        params = params // {
          weight = 10;
        };
      }
    ];
}
