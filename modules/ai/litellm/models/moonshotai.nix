{ lib, ... }:
let
in
{
  kimi-k2 =
    let
      params = {
        # https://docs.unsloth.ai/basics/kimi-k2-how-to-run-locally
        temperature = 0.6;
        min_p = 0.01;
      };
    in [
    {
      model = "groq/moonshotai/kimi-k2-instruct-0905"; # primary
      params = { # additional params are unsupported
        weight = 10;
      };
    }
    {
      model = "openrouter/moonshotai/kimi-k2:free";
      params = params // {
        weight = 10;
      };
    }
  ];
}
