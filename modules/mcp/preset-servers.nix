{
  config,
  pkgs,
  lib,
  ...
}:
let
  purePkgs = import <nixpkgs> { }; # to avoid build ungoogled-chromium because it uses too much RAM
in
{
  arxiv = {
    command = lib.getExe pkgs.mcp-server-arxiv;
    args = [ ];
  };
  devtools = {
    command = lib.getExe pkgs.mcp-server-devtools;
    args = [ ];
    env = {
      # TODO: refactor. now depends on local searxng instance.
      SEARXNG_BASE_URL = lib.concatStringsSep "," [
        "http://localhost:16060"
      ];
      ENABLE_ADDITIONAL_TOOLS = lib.concatStringsSep "," [
        "sequential-thinking" # instead of think
        "vulnerability_scan"
        "sbom"
        "security"
        "security_override"
      ];
      DISABLED_FUNCTIONS = lib.concatStringsSep "," [
        "aws_documentation"
        "devtools_help"
        "murican_to_english"
        "q-developer-agent"
        "shadcn"
        "terraform_documentation"
        "think"
      ];
    };
  };
  git = {
    command = lib.getExe pkgs.mcp-server-git;
    args = [ ];
  };
  nixos = {
    command = lib.getExe pkgs.mcp-server-nixos;
    args = [ ];
  };
  excel = {
    command = lib.getExe pkgs.mcp-server-excel;
    args = [ "stdio" ];
  };
  playwright = {
    # Use ungoogled-chromium
    command = lib.getExe pkgs.mcp-server-playwright;
    args = [
      "--executable-path"
      "${lib.getExe purePkgs.ungoogled-chromium}"
    ];
  };
  "pdf-reader" = {
    command = lib.getExe pkgs.mcp-server-pdf-reader;
    args = [ ];
  };
  markitdown = {
    command = lib.getExe pkgs.mcp-server-markitdown;
    args = [ ];
  };
  ocr = {
    command = lib.getExe pkgs.mcp-server-ocr;
    args = [ ];
  };
  quickchart = {
    command = lib.getExe pkgs.mcp-server-quickchart;
    args = [ ];
  };
  jetbrains = {
    command = lib.getExe pkgs.mcp-server-jetbrains;
    args = [ ];
  };
  serena = {
    command = lib.getExe pkgs.serena;
    args = [
      "start-mcp-server"
      "--enable-web-dashboard"
      "false"
    ];
  };
  atlassian = {
    # TODO: may be able to replace to "url"
    command = lib.getExe pkgs.mcp-server-remote;
    args = [
      "https://mcp.atlassian.com/v1/sse"
    ];
  };
  azure-devops = {
    command = lib.getExe pkgs.mcp-server-azure-devops;
    args = [
      "!! input your organization manually !!!"
    ];
  };
  spec-workflow = {
    command = lib.getExe pkgs.mcp-server-spec-workflow;
    args = [
      "/path/to/your/project"
      "--AutoStartDashboard"
    ];
  };
  lsp = {
    command = lib.getExe pkgs.mcp-server-lsp;
    args = [
      "!! input your organization manually !!!"
    ];
  };
  mysql = {
    command = lib.getExe pkgs.mcp-server-mysql;
    args = [ ];
    env = {
      MYSQL_HOST = "127.0.0.1";
      MYSQL_PORT = "3306";
      MYSQL_USER = "root";
      MYSQL_PASS = "your_password";
      MYSQL_DB = "your_database";
      ALLOW_INSERT_OPERATION = "false";
      ALLOW_UPDATE_OPERATION = "false";
      ALLOW_DELETE_OPERATION = "false";
    };
  };
  wireshark = {
    command = lib.getExe pkgs.mcp-server-wireshark;
    args = [ ];
  };
  textlint = lib.optionalAttrs config.my.home.documentation.enable {
    command = "${config.my.home.documentation.executablePath}/bin/textlint";
    args = [
      "--mcp"
    ];
  };
  yfinance = {
    command = lib.getExe pkgs.mcp-server-yfinance;
    args = [ ];
  };
  investor-agent = {
    command = lib.getExe pkgs.mcp-server-investor-agent;
    args = [ ];
  };
  wakapi = {
    env = {
      WAKAPI_URL = "http://localhost:3000";
      WAKAPI_API_KEY = "your-api-key";
    };
    command = lib.getExe (builtins.getFlake "github:impure0xntk/mcp-wakapi/85c2ac01e4926b00d3a709538d492cfbf813e1e1")
    .packages.x86_64-linux.default;
    args = [ ];
  };
  vscode = {
    # see the bottom of this file
    command = lib.getExe pkgs.mcp-server-remote;
    args = [
      "http://localhost:13001/mcp"
    ];
  };
}
