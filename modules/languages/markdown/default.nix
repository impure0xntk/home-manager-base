{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.my.home.languages.markdown;

  rumdlConfigPath = lib.my.toToml cfg.lint.config;
in
{
  options.my.home.languages.markdown = {
    enable = lib.mkEnableOption "Whether to enable markdown language support.";
    lint.config = lib.mkOption {
      type = lib.types.attrs;
      default = {
        MD007 = {
          indent = 4;
        };
        MD013 = false;
      };
      description = "Markdownlint config.";
    };
  };
  config = lib.mkIf cfg.enable {
    my.home.editors.lspConfig = {
      marksman.cmd = [ "${lib.getExe pkgs.unstable.marksman}" "server" ];
      markdown_oxide.cmd = [ "${lib.getExe pkgs.unstable.markdown-oxide}" "server" ];
      panache.cmd = [ "${lib.getExe pkgs.unstable.panache}" "lsp" ];
      rumdl.cmd = [ "${lib.getExe pkgs.unstable.rumdl}" "server"
        "--config" rumdlConfigPath ];

      # Previewer
      mpls.cmd = [ "${lib.getExe pkgs.unstable.mpls}" "--theme" "dark" "--enable-emoji" "--enable-footnotes" "--no-auto" ];
    };
    programs.vscode.profiles.default = {
      extensions = pkgs.nix4vscode.forVscode [
        "shd101wyy.markdown-preview-enhanced"
        "rvben.rumdl"
        "arr.marksman"
        "jolars.panache"
      ];
      userSettings = {
        "[markdown]" = {
          "editor.defaultFormatter" = "rvben.rumdl";
        };
        "rumdl.configPath" = rumdlConfigPath; # workaround of infinite recursion
      } // lib.my.flatten "_flattenIgnore" {
        rumdl = {
          server.path = "${lib.getExe pkgs.unstable.rumdl}";
          fixOnSave = true;
        };
        markdown-preview-enhanced = {
          enableExtendedTableSyntax = true;
          previewTheme = "github-light.css";
        };
        marksman = {
          customCommand = "${pkgs.unstable.marksman}/bin/marksman";
          trace.server = "messages";
        };
        panache = {
          commandPath = lib.getExe pkgs.unstable.panache;
          downloadBinary = false;
          experimental.incrementalParsing = true;
        };
      };
    };
  };

}
