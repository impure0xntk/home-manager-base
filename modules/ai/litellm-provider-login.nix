# Instructions: https://docs.litellm.ai/docs/providers/chatgpt#sign-in-before-starting-the-proxy
# 1. Add this to path and executte "litellm-<provider name>-login" in the terminal
# 2. Login with device-code then generate "auth.json" in the current directory
# 3. Copy "auth.json" to "<PROVIDER NAME>_TOKEN_DIR" for litellm proxy

{ pkgs, lib, providerName, ... }:

let
  tokenDirEnvVarName = "${lib.toUpper providerName}_TOKEN_DIR";

  litellmPython = pkgs.python3.withPackages (ps: [
    ps.litellm
  ] ++ ps.litellm.optional-dependencies.proxy);

  litellmChatgptLogin = pkgs.writeShellApplication {
    name = "litellm-${providerName}-login";

    runtimeInputs = [
      litellmPython
    ];

    text = ''
      export ${tokenDirEnvVarName}="."

      python -c 'from litellm.llms.${providerName}.authenticator import Authenticator; Authenticator().get_access_token()'
    '';
  };
in litellmChatgptLogin
