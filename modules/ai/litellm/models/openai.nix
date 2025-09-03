# For github copilot:
# 1. Run litellm manually to auth device: input code
#    Use "systemctl cat --user litellm.service" ans exec ExecStart command from interactive commandline.
# 2. You can start litellm automatically.
# For details, see https://docs.litellm.ai/docs/providers/github_copilot
{ lib, ... }:
let
  githubCopilotDummySettings = {
    extra_headers = {
      "Editor-Version" = "vscode/1.103.2";
      "Copilot-Integration-Id" = "vscode-chat";
    };
  };
in
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
  "gpt-4.1" = [
    {
      model = "github_copilot/gpt-4.1";
      params = {
        weight = 10;
      } // githubCopilotDummySettings;
    }
  ];
  gpt-4o = [
    {
      model = "github_copilot/gpt-4o";
      params = {
        weight = 10;
      } // githubCopilotDummySettings;
    }
  ];
}