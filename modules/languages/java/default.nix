# Set java jdk as the follows:
# * config.programs.java.package: default jdk for development and JAVA_HOME
# * pkgs.jdk: latest jdk for java tools
{ pkgs, lib, config, ... }:
let
  cfg = config.my.home.languages.java;
  cfgNetworks = config.my.home.networks;

  maven = pkgs.my.maven-customized.override { # customized for compiler and opts.
    compileJdk = config.programs.java.package; };
  mvnd = pkgs.my.mvnd;
  pmd = pkgs.my.pmd;

  tunedJavaArgs = [
    "-XX:+UseStringDeduplication"
    "-XX:+UseZGC" # "-XX:+ZGenerational" is the default.
    "-XX:+UseLargePages"
    # "-XX:+UseCompactObjectHeaders" # will be default in Java 27
  ];

  jdtlsSettings = rec {
    memory = {
      min = "4g";
      max = "8g";
    };
    sharedIndexLocation = "${config.xdg.cacheHome + "/.jdt/index"}"; # shared index location for jdtls.
    lombokJar = "${pkgs.lombok}/share/java/lombok.jar";
    initializationOptions.settings = {
      java = {
        configuration = {
          updateBuildConfiguration = "interactive";
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
        };
        jdt.ls = {
          protobufSupport.enable = true;
          groovySupport.enable = false;
          kotlinSuport.enable = false;
          scalaSupport.enable = false;
          aspectjSupport.enable = false;
          androidSupport.enable = false;
          # javac.enabled = true;
        };

        maxConcurrentBuilds = 2;

        home = pkgs.jdk;
        telemetry = false;
        format.onType.enabled = false;
        inlayHints.parameterNames.enabled = "all";
        diagnostic.nullAnalysis ={
          mode = "automatic";
          nonnull = [ "jakarta.annotation.Nonnull" "org.jspecify.annotations.NonNull" ];
          nullable = [ "jakarta.annotation.Nullable" "org.jspecify.annotations.Nullable" ];
          nonnullbydefault = [ "org.jspecify.annotations.NullMarked" ];
        };
      };
    };
    vmArgs = {
      vscode = tunedJavaArgs ++ [
        "-Xms${jdtlsSettings.memory.min}"
        "-Xmx${jdtlsSettings.memory.max}"
        # shared index location and lombok support are set in extension settings.
      ];
      zed = tunedJavaArgs ++ [
        # memory options are set in extension settings, but not work
        "-Xms${jdtlsSettings.memory.min}"
        "-Xmx${jdtlsSettings.memory.max}"

        "-Djdt.core.sharedIndexLocation=${sharedIndexLocation}"
      ];
    };
  };

  # Vmargs for VS code tools.
  # It includes tuned java args, and proxy if needed.
  toolsVscodeVmargs = (lib.concatStringsSep " " tunedJavaArgs)
    + (lib.optionalString cfgNetworks.proxy.enable (" " + cfgNetworks.proxy.snippet.javaOpts)); # consider proxy

  scripts = import ./script.nix { inherit pkgs lib config; };

  jdtlsForZed = pkgs.writeShellApplication {
    name = "jdtls";
    runtimeInputs = [ pkgs.unstable.jdt-language-server ];
    text = ''
      exec jdtls \
        ${lib.concatStringsSep " " (lib.forEach jdtlsSettings.vmArgs.zed (arg: "--jvm-arg=${arg}"))} \
        "''$@"
    '';
  };

  # Use community fork of palantir-java-format, for all deps jar.
  open-java-format = pkgs.fetchurl {
    url = "https://github.com/openjavaformat/open-java-format/releases/download/2.98.0.6/open-java-format-2.98.0.6-all.jar";
    hash = "sha256-UgmMvkSwNENOItD9atJl+ttzUEG7EsiWLU7nzb/ebUg=";
  };
  java-debug-plugin = pkgs.fetchurl {
    url = "https://github.com/zed-industries/java-debug/releases/download/0.53.2/com.microsoft.java.debug.plugin-0.53.2.jar";
    hash = "sha256-UnUZWQUBXOeG/GMYyNA5/vQ6H62h0DrN7CTGmjubqDw=";
  };
in {
  options.my.home.languages.java.enable = lib.mkEnableOption "Java development environment";

  config = lib.mkIf cfg.enable {
    home.packages = (
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
        mvnd.home=${mvnd}
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
      package = lib.mkDefault pkgs.jdk;
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
          java = with jdtlsSettings.initializationOptions.settings.java; {
            jdt.ls = jdt.ls // {
              java.home = "${pkgs.jdk}"; # config.programs.java.package;
              vmargs = lib.concatStringsSep " " jdtlsSettings.vmArgs.vscode;
            };
            configuration = configuration // {
              detectJdksAtStart = false;
            };

            compile.nullAnalysis = diagnostic.nullAnalysis;
            debug.settings = {
              showHex = true;
              showQualifiedNames = false;
              showLogicalStructure = true;
            };
            format = format;
            inlayHints = inlayHints;
            maxConcurrentBuilds = maxConcurrentBuilds;

            # Experimental so if not work, remove them.
            # "java.jdt.ls.javac.enabled" = if (lib.versionAtLeast pkgs.jdk.version "24") then "on" else "off" ;
            # "java.completion.engine" = "dom";
            sharedIndexes = {
              enabled = "on";
              location= jdtlsSettings.sharedIndexLocation;
            };
          };

          apexPMD = {
            commandBufferSize = 100;
            enableCache = true;
            jrePath = "${pkgs.jdk}";
            pmdBinPath = "${pmd}"; # directory, not bin path.
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
            analysisExcludesStandalone = "**/*.json,**/*.jsonc,**/*.yaml,**/*.yml,**/*.xml";
          };

          xml = {
            java.home = "${pkgs.jdk}";
            format.enabled = false; # if enabled format on save.
            codeLens.enabled = true;
            # xml.server is defined by modules/ide/vscode/default.nix
          };
        };

        extensions = pkgs.nix4vscode.forVscode [
          "vscjava.vscode-java-pack"
          "redhat.java"
          "vscjava.vscode-java-debug"
          "vscjava.vscode-java-test"
          "vscjava.vscode-maven"
          "vscjava.vscode-java-dependency"
          "dgileadi.java-decompiler"
          "sonarsource.sonarlint-vscode"
          "shengchen.vscode-checkstyle"
          "chuckjonas.apex-pmd"
        ];
      };
    };
    programs.zed-editor = {
      userSettings = {
        languages."Java".formatter = {
          external = {
            command = "${pkgs.jdk}/bin/java";
            arguments = [
              "-jar"
              open-java-format
              # "--palantir" # https://github.com/openjavaformat/open-java-format#coming-from-palantir-java-format
              "-"
            ];
          };
        };

        lsp.jdtls = {
          settings = {
            java_home = pkgs.jdk;
            jdk_auto_download = false;

            jdtls_launcher = lib.getExe jdtlsForZed;

            lombok_support = true;
            lombok_jar = jdtlsSettings.lombokJar;

            java_debug_jar = java-debug-plugin;

            # Not work
            min_memory = jdtlsSettings.memory.min;
            max_memory = jdtlsSettings.memory.max;

            initialization_options = jdtlsSettings.initializationOptions;
          };
        };
      };
    };
    programs.zed-editor-extensions = {
      packages = with pkgs.zed-extensions; [
        java
      ];
    };
    my.home.ai.harness.sandbox.profiles =
    let
      excludes = [
        "target"
        ".mvn"
        ".gradle"
        "~/.m2"
      ];
      includes = [
        "~/.m2/settings.xml" # includes tokens
      ];
      filesystem = {
        allowRead = excludes;
        allowWrite = excludes;
        allowExecute = excludes;
        denyRead = includes;
        denyWrite = includes;
        denyExecute = includes;
      };
    in {
      fence.settings = {
        inherit filesystem;
      };
      yolo.settings = {
        inherit filesystem;
      };
    };
  };
}
