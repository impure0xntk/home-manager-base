# Set java jdk as the follows:
# * config.programs.java.package: default jdk for development and JAVA_HOME
# * pkgs.jdk: latest jdk for java tools
{ pkgs, lib, config, ... }:
let
  cfg = config.my.home.languages.java;
  cfgNetworks = config.my.home.networks;

  maven = pkgs.maven-customized.override { # customized for compiler and opts.
    compileJdk = config.programs.java.package; };

  # Vmargs for VS code tools.
  # It includes tuned java args, and proxy if needed.
  toolsVscodeVmargs = (lib.concatStringsSep " " pkgs.tunedJavaArgs)
    + (lib.optionalString cfgNetworks.proxy.enable (" " + cfgNetworks.proxy.snippet.javaOpts)); # consider proxy

  scripts = import ./script.nix { inherit pkgs lib config; };
in {
  options.my.home.languages.java.enable = lib.mkEnableOption "Java development environment";

  config = lib.mkIf cfg.enable {
    home.packages =
      with pkgs; (
        [ maven mvnd pmd ] # Development
        # ++ [netbeans] # Swing GUI development
        # ++ [jvm-tools azul-mission-control] # Analysis
      )
      ++ scripts;

    home.sessionVariables = {
      MAVEN_PATH = lib.getExe pkgs.maven;
    };

    home.file = {
      # TODO: check whether mvnd.jvmArgs works.
      # For default details, see https://github.com/apache/maven-mvnd/blob/master/dist/src/main/distro/conf/mvnd.properties
      ".m2/mvnd.properties".text = ''
        # mvnd.jvmArgs =
        mvnd.home=${pkgs.mvnd}
      '';

      ".m2/toolchians.xml".text = ''
        <toolchains>
          <toolchain>
            <type>jdk</type>
            <provides>
              <version>${lib.versions.major config.programs.java.package.version}</version>
            </provides>
            <configuration>
              <jdkHome>${config.programs.java.package}</jdkHome>
            </configuration>
          </toolchain>
          <toolchain>
            <type>jdk</type>
            <provides>
              <version>${lib.versions.major pkgs.jdk.version}</version>
            </provides>
            <configuration>
              <jdkHome>${pkgs.jdk}</jdkHome>
            </configuration>
          </toolchain>
        </toolchains>
      '';
    };

    programs.bash.shellAliases = {
      # maven aliases
      "mdi" = "mvnd -DskipTests -Dmaven.test.skip=true install";
      "mdci" = "mvnd -DskipTests -Dmaven.test.skip=true clean install";
      "mdt" = "mvnd -DskipTests=false install";
    };

    programs.java = {
      enable = true;
      package = lib.mkDefault pkgs.zulu17;
    };

    # For java application "/run/user/$UID/doc operation not permitted." workaround.;
    # Based on xdg-document-portal.service.
    systemd.user.services.xdg-document-portal = lib.optionalAttrs config.my.home.desktop.enable {
      Unit = {
        Description = "Overrode: xdg-documentation-portal.service";
        Documentation = [
          "https://bugzilla.redhat.com/show_bug.cgi?id=1913358"
          "https://askubuntu.com/questions/1227667/df-command-throws-error-on-run-user-1000-doc-folder"
        ];
      };
      # ExecStart override tip: https://askubuntu.com/a/659268
      Service.ExecStart = [
        ""
        "${pkgs.coreutils-full}/bin/true"
      ];
    };

    programs.vscode = {
      # TODO: separate profiles from default.
      profiles.default = {
        userSettings = {
          "[java]" = {
            "editor.defaultFormatter" = "redhat.java";
          };
        } // lib.my.flatten "_flattenIgnore" {
          # "Runtime at '{jdk path}' is incompatible with the 'JavaSE-NN' environment." workaround.
          java = {
            jdt.ls = {
              java.home = "${pkgs.jdk}"; # config.programs.java.package;
              vmargs = lib.concatStringsSep " " pkgs.tunedJavaArgs;
            };
            configuration = {
              detectJdksAtStart = false;
              runtimes = [ # name allows "JavaSE-NN" only.
                {
                  "name" = "JavaSE-${lib.versions.major config.programs.java.package.version}";
                  "path" = config.programs.java.package;
                  "default" = true;
                }
                (
                  # Cannot set GraalVM as JavaSE.
                  # Maybe should use "GraalVM Tools for Java" extension.
                  lib.mkIf (!lib.hasPrefix "graalvm" pkgs.jdk.name) {
                    "name" = "JavaSE-${lib.versions.major pkgs.jdk.version}";
                    "path" = pkgs.jdk;
                    "default" = false;
                  }
                )
              ];
              updateBuildConfiguration = "interactive";
            };

            compile.nullAnalysis = {
              mode = "automatic";
              nonnull = [ "jakarta.annotation.Nonnull" ];
              nullable = [ "jakarta.annotation.Nullable" ];
            };
            debug.settings = {
              showHex = true;
              showQualifiedNames = false;
              showLogicalStructure = true;
            };
            format.onType.enabled = false;
            inlayHints.parameterNames.enabled = "all";

            # Experimental so if not work, remove them.
            # "java.jdt.ls.javac.enabled" = if (lib.versionAtLeast pkgs.jdk.version "23") then "on" else "off" ;
            # "java.completion.engine" = "dom";
            sharedIndexes = {
              enabled = "on";
              location= config.xdg.cacheHome + "/.jdt/index";
            };
          };

          apexPMD = {
            commandBufferSize = 100;
            enableCache = true;
            jrePath = "${pkgs.jdk}";
            pmdBinPath = "${pkgs.pmd}"; # directory, not bin path.
            runOnFileChange = true;
            onFileChangeDebounce = 3000;
          };

          redhat.telemetry.enabled = false;

          sonarlint = {
            ls = {
              javaHome = "${pkgs.jdk}";
              vmargs = toolsVscodeVmargs;
            };
            disableTelemetry = true;
            # To suppress "SonarQube for VS Code failed to analyze JSON/yaml code: Node.js runtime version 18.17.0 or later is required."
            analysisExcludesStandalone = "**/*.json,**/*.jsonc,**/*.yaml,**/*.yml";
          };

          xml = {
            java.home = "${pkgs.jdk}";
            format.enabled = false; # if enabled format on save.
            codeLens.enabled = true;
            server = rec {
              workDir = "${config.xdg.cacheHome}/.lemminx";
              binary.path = lib.getExe pkgs.lemminx;
              binary.trustedHashes = ["${builtins.hashFile "sha256" binary.path}"]; # For lemminx(unnecessary). "xml.server.binary.trustedHashes" works only User settings.
              preferBinary = true;
              vmargs = toolsVscodeVmargs;
            };
          };
        };

        extensions = pkgs.nix4vscode.forVscode [
          "vscjava.vscode-java-pack"
          "redhat.java.1.41.1" # 1.42.0 is not available for some java project
          "vscjava.vscode-java-debug"
          "vscjava.vscode-java-test"
          "vscjava.vscode-maven"
          "vscjava.vscode-java-dependency"
          "dgileadi.java-decompiler"
          "sonarsource.sonarlint-vscode"
          "shengchen.vscode-checkstyle"
          "chuckjonas.apex-pmd"
          "redhat.vscode-xml"
          "ferib.proguard-language"
          "CucumberOpen.cucumber-official" # TODO: move to work
        ];
      };
    };
  };
}
