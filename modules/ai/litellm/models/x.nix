{ lib, ... }:
{
  "grok-4-fast" = [
    {
      model = "openrouter/x-ai/grok-4-fast:free";
      params = {
        weight = 10;
      };
    }
  ];
}
