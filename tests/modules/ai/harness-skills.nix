{ config, lib, ... }:

{
  config = {
    my.home.ai.harness = {
      enable = true;
      skills."5-whys" = {
        url = "https://github.com/awesome-skills/5-whys-skill";
        revision = "353a57673f1978de4b47fb363bb065e2547fd024";
        hash = "sha256-Ixil5JL3Jtwl+/+Wv3hGg+yGvLBrtFdkzjCq/58gjD8=";
      };
    };

    assertions = [
      {
        assertion = lib.hasAttr "ai/skills/5-whys" config.xdg.configFile;
        message = "A repository with a root SKILL.md must be installed as one skill.";
      }
    ];
  };
}
