{ lib, ... }:

{
  "horizon-beta" = [
    {
      model = "openrouter/openrouter/horizon-beta";
      params = {
        weight = 10;
      };
    }
  ];
  "glm-4.5-air" = [
    {
      model = "openrouter/z-ai/glm-4.5-air:free";
      params = {
        weight = 10;
      };
    }
  ];
}