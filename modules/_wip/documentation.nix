{ pkgs, lib, config, ... }:
let
  # Tips
  # * pandoc
  #   * If want to make table with colspan, graphviz digraph and <tr><td> is recommend.

  selfBuiltins = import ./lib/builtins { inherit pkgs lib; };
  pandocFetchedFilters = {
    pagebreak = pkgs.fetchurl {
        url = https://raw.githubusercontent.com/pandoc-ext/pagebreak/3f92f93a7f6c6420c5d5c7051f7d6c58150c50e7/pagebreak.lua;
        hash = "sha256-MIcoK7DNzAjTSGqxbo3EqevoRsXFY1AiIH866fGjGuc=";
      };
    list-table = pkgs.fetchurl {
        url = https://raw.githubusercontent.com/pandoc-ext/list-table/fc93e5e8d9b5e179184953608d5476cd18e1051a/list-table.lua;
        hash = "sha256-w8xcJTLpV9cb8/iX54dVgAN6FyMmrTjb5KrvBTHOsJo=";
      };
    section-bibliographies = pkgs.fetchurl {
        url = https://raw.githubusercontent.com/pandoc-ext/section-bibliographies/5b4180c49b3d41974711ed1b74c80548ad42e404/_extensions/section-bibliographies/section-bibliographies.lua;
        hash = "sha256-TO3WAYLting08L1l2GfQtyRyAGwOknaDKvnZntU4oNs=";
      };
  };
  pandocConfig = rec {
    defaults = rec {
      common = {
        table-of-contents = false;
        standalone = true;
        self-contained = true;
        toc-depth = 2;
        wrap = "none";
        highlight-style = "tango";
        filters = with pandocFetchedFilters; [
          "pandoc-include"
          "pandoc-acro"
          # By default, disabled plantuml filter for markup langs
          # because this generates images and add links, not embed images.

          pagebreak
          list-table
          section-bibliographies
        ];
        css = [
          # "${config.xdg.configHome}/pandoc/css/common.css"
        ];
      };
      xdgConfigFileCommonPath = "pandoc/defaults/common.yaml"; # if changed, change vscode markdown-preview-enhanced settings.json too.
    };
    # css = {
    #   common = ''
    #     .page-break {
    #         page-break-before:always;
    #     }
    #   '';
    # };
    commandSnippet = {
      common = "pandoc --verbose -d $XDG_CONFIG_HOME/${defaults.xdgConfigFileCommonPath}";
    };
    functionSnippet = rec {
      common = {from, to, extraOptions ? ""}: {
        description = "pandoc ${from} to ${to}";
        wraps = "pandoc";
        body = ''
          ${commandSnippet.common} \
            --from=${from} --to=${to} ${extraOptions} $argv
        '';
      };
      markdownTo = {to, extraOptions ? ""}:
        common {inherit to extraOptions; from = "markdown+hard_line_breaks";};
    };
  };
  plantuml = if config.programs.java.enable then (pkgs.plantuml.override { jre = config.programs.java.package; }) else pkgs.plantuml;
in rec {
  home.packages = with pkgs; [
    # UML
    graphviz-nox
    plantuml # requires X11

    pandoc-include
    pandoc-acro
    pandoc-plantuml-filter
  ];

  programs.pandoc.enable = true;
  xdg.configFile = with pandocConfig; {
    "pandoc/defaults/common.yaml" = {
      recursive = true;
      source = selfBuiltins.toYaml defaults.common;
    };
    # "pandoc/css/common.css" = {
    #   recursive = true;
    #   source = selfBuiltins.toYaml css.common;
    # };
  };
  programs.bash.shellAliases."pandoc" = pandocConfig.commandSnippet.common;
  programs.fish.functions = with pandocConfig; {
    pandoc-md-docx = functionSnippet.markdownTo {
      to = "docx";
      extraOptions = "--toc=true --filter=pandoc-plantuml";
    };
    pandoc-md-pdf = functionSnippet.markdownTo {
      to = "pdf";
      extraOptions = "--toc=true --filter=pandoc-plantuml";
    };
    pandoc-md-ghm = functionSnippet.markdownTo {
      to = "markdown_github+hard_line_breaks-simple_tables-multiline_tables-grid_tables";
    };
    pandoc-md-html = functionSnippet.markdownTo {
      to = "html";
      extraOptions = "--filter=pandoc-plantuml";
    };
  };
}
