# TODO: add gemini api
{ lib, ... }:
let
in
{
  "gemini-2.5-pro" = [
      {
        model = "gemini/gemini-2.5-pro";
        params = {
          weight = 10;

          # 2025/07
          tpm = 250000;
          rpm = 5;
        };
      }
    ];
  "gemini-2.5-flash" = [
      {
        model = "gemini/gemini-2.5-flash";
        params = {
          weight = 10;
          fallbacks = [
            "gemini-2.5-flash-lite"
          ];

          # 2025/07
          tpm = 250000;
          rpm = 10;
        };
      }
    ];
  "gemini-2.5-flash-lite" = [
      {
        model = "gemini/gemini-2.5-flash-lite";
        params = {
          weight = 10;

          # 2025/07
          tpm = 250000;
          rpm = 15;
        };
      }
    ];
  "gemini-2.0-flash" = [
      {
        model = "gemini/gemini-2.0-flash";
        params = {
          weight = 10;
          fallbacks = [
            "gemini-2.0-flash-lite"
          ];

          # 2025/07
          tpm = 1000000;
          rpm = 15;
        };
      }
      {
        model = "openrouter/google/gemini-2.0-flash-exp:free";
        params = {
          weight = 10;
        };
      }
    ];
  "gemini-2.0-flash-lite" = [
      {
        model = "gemini/gemini-2.0-flash-lite";
        params = {
          weight = 10;

          # 2025/07
          tpm = 1000000;
          rpm = 30;
        };
      }
    ];

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
        model = "gemini/gemma-3-27b-it";
        params = params // {
          weight = 10;

          # 2025/07
          tpm = 15000;
          rpm = 30;
        };
      }
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

        max_output_tokens = 32768;
        max_input_tokens = 32768;
      };
    in
    [
      {
        model = "gemini/gemma-3n-e4b-it";
        params = params // {
          weight = 10;

          # 2025/07
          tpm = 15000;
          rpm = 30;
        };
      }
      {
        model = "openrouter/google/gemma-3n-e4b-it:free";
        params = params // {
          weight = 10;
        };
      }
    ];
}
