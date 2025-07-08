{
  config,
  lib,
  ...
}:
let
  cfg = config.my.home.networks;
  cfgNixOS = config.my.home.core.nixos;

  # https://github.com/NixOS/nixpkgs/blob/nixos-24.11/nixos/modules/config/networking.nix
  envVarsLower = [
    "http_proxy"
    "https_proxy"
    "rsync_proxy"
    "ftp_proxy"
    "all_proxy"
  ];
  envVars = envVarsLower ++ (lib.forEach envVarsLower lib.toUpper);

  noProxyHosts = ["127.0.0.1" "localhost" cfg.hostname];
  noProxyVar = lib.concatStringsSep "," noProxyHosts;

  respectsNixOS = lib.my.traceSeqWith "my.home.networks respects NixOS" cfgNixOS.enable;
in
{
  # Enable this from ${project root}/home/modules/core
  options.my.home.networks = {
    hostname = lib.mkOption {
      type = lib.types.str;
      description = "hostname";
      example = "nixos";
    };
    proxy = {
      default = lib.mkOption {
        type = lib.types.str;
        description = "proxy url";
        default = builtins.getEnv "https_proxy";
        example = "https://example.com:3128";
      };
      enable = lib.mkOption {
        type = lib.types.bool;
        description = "Whether to enable proxy. Do not edit this: set my.home.networks.proxy.default directly.";
        default = lib.stringLength config.my.home.networks.proxy.default > 0;
      };
      snippet = {
        withoutSchema = lib.mkOption {
          type = lib.types.str;
          description = "Proxy without schema for connect command. Do not edit this: set from my.home.networks.proxy.default.";
          default = lib.lists.last (lib.strings.splitString "://" cfg.proxy.default);
          example = "example.com:3128";
        };
        javaOpts = lib.mkOption {
          type = lib.types.str;
          description = "Proxy opts for java. Do not edit this: set from my.home.networks.proxy.default.";
          default = lib.my.genJavaOpts
            (lib.my.genJavaProxyOptsAttr cfg.proxy.snippet.withoutSchema noProxyHosts);
          example = "-Dhttps.proxyHost=\"example.com\" -Dhttps.proxyPort=\"3128\"";
        };
      };
    };
  };
  config.assertions = [
      {
        assertion = cfg.hostname != "";
        message = "Set hostname.";
      }
    ];
  config.home = (lib.mkIf (!respectsNixOS && cfg.proxy.enable) {
    sessionVariables = lib.my.traceSeqWith "my.home.networks sessionVariables for proxy" (
    (builtins.listToAttrs (builtins.map (n: {name = n; value = cfg.proxy.default;}) envVars))
    // {
      "no_proxy" = noProxyVar;
      "NO_PROXY" = noProxyVar;
    });
  });
}
