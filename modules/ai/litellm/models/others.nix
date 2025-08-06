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
}