{ lib, ... }:

{
  "glm-4.5-air" = [
    {
      model = "openrouter/z-ai/glm-4.5-air:free";
      params = {
        weight = 10;
      };
    }
  ];
  "tongyi-deepresearch" = [
    {
      model = "openrouter/alibaba/tongyi-deepresearch-30b-a3b:free";
      params = {
        weight = 10;
      };
    }
  ];
}