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
  "claude-sonnet-3.5" = [
    {
      model = "github_copilot/claude-3.5-sonnet";
      params = {
      } // githubCopilotDummySettings;
    }
  ];
  "claude-sonnet-4" = [
    {
      model = "github_copilot/claude-sonnet-4";
      params = {
      } // githubCopilotDummySettings;
    }
  ];
}