# TODO: add deepseek official model
{ ... }:
let
in
{
  deepseek-r1 = [
    {
      model = "openrouter/deepseek/deepseek-r1-0528:free";
      params = {
        # https://docs.unsloth.ai/basics/deepseek-r1-0528-how-to-run-locally
        temperature = 0.6;
        top_p = 0.95;
        min_p = 0.01;
      };
    }
    {
      model = "openrouter/deepseek/deepseek-r1:free";
      params = {
      };
    }
  ];
  deepseek-v3 = [
    {
      model = "openrouter/deepseek/deepseek-chat-v3-0324:free";
      params = {
        # https://docs.unsloth.ai/basics/tutorials-how-to-fine-tune-and-run-llms/deepseek-v3-0324-how-to-run-locally
        # For coding.
        temperature = 0.6;
        min_p = 0;
      };
    }
  ];
  "deepseek-v3.1" = [
    {
      model = "openrouter/deepseek/deepseek-chat-v3.1:free";
      params = {
      };
    }
  ];
  deepseek-r1t2-chimera = [
    {
      model = "openrouter/tngtech/deepseek-r1t2-chimera:free";
      params = {
      };
    }
  ];
  deepseek-r1t-chimera = [
    {
      model = "openrouter/tngtech/deepseek-r1t-chimera:free";
      params = {
      };
    }
  ];
}
