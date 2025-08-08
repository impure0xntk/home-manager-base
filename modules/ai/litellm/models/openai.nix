{ lib, ... }:

{
  "gpt-oss" = [
    {
      model = "openrouter/openai/gpt-oss-20b:free";
      params = {
        weight = 10;

        temperature = 0.6;
        top_p = 1.0;
        top_k = 0;
      };
    }
  ];
}