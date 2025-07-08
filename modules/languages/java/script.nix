# utilityScripts
{ pkgs, lib, config, ... }:
let
  scripts = rec {
    mvnLocalRepositoryPath = pkgs.writeShellApplication {
      name = "mvn-localrepopath";
      text = ''
        mvn help:evaluate -Dexpression=settings.localRepository -q -DforceStdout
        '';
    };
    mvnDependClassPath = pkgs.writeShellApplication {
      name = "mvn-depend-classpath";
      excludeShellChecks = ["SC2154"];
      text = ''
        tmpfile=$(mktemp)
        mvn -q dependency:build-classpath -DoutputAbsoluteArtifactFilename=true -Dmdep.outputFile="$tmpfile" "$@"
        sort "$tmpfile" | uniq
        '';
    };
    mvnClassPath = pkgs.writeShellApplication {
      name = "mvn-classpath";
      text = ''
        mvn -q exec:exec -Dexec.executable=echo -Dexec.args="%classpath" "$@" \
          | tr '\n' ':' \
          | rev | cut -c2- | rev # to trim last separator :
        '';
    };
    mvnDelombok = pkgs.writeShellApplication {
      name = "mvn-delombok";
      runtimeInputs = [mvnClassPath mvnLocalRepositoryPath pkgs.fd];
      text = ''
        #######################################
        # Delombok maven source
        #
        # Globals:
        #
        #   CLASSPATH: for lombok
        #   LOMBOK_JAR: for lombok
        # Arguments:
        #   1: classpath. default: "$(mvn-depend-classpath):$lombok_jar"
        #   2-: delombok argument
        #######################################

        LOMBOK_JAR="''${LOMBOK_JAR:-"$(fd --type f "lombok-.*\d+.jar\$" "$(mvn-localrepopath)" \
          | sort -r | head -n 1)"}" # latest lombok

        CLASSPATH="''${CLASSPATH:-"$(mvn-classpath):$LOMBOK_JAR"}"

        java -jar "''${LOMBOK_JAR:-lombok was not found.}" \
          delombok \
          --classpath="$CLASSPATH" \
          --module-path="$CLASSPATH" \
          "$@"
      '';
    };
    mvnClassDiagram = pkgs.writeShellApplication {
      name = "mvn-classdiagram";
      runtimeInputs = with pkgs; [jdk UMLDoclet fd]
        ++ [mvnClassPath mvnLocalRepositoryPath mvnDelombok];
      text = ''
        #######################################
        # Generate maven source class-diagram
        #
        # Globals:
        #
        #   CLASSPATH: for lobok and javadoc
        #   LOMBOK_JAR: for lombok
        # Arguments:
        #   1: sourcepath: ex test/src/main/java
        #   2: package name: com.example.test
        #   3-: javadoc args
        #######################################

        test -n "''${1:?input sourcepath}"
        test -n "''${2:?input package name}"
        sourcepath="$1"
        subpackages="$2"
        shift 2

        # For opening diagram from browser, does not remove tmpdir with trap.
        tmpdir="$(mktemp -d)"

        # For provided scope like lombok, add specific module path
        LOMBOK_JAR="''${LOMBOK_JAR:-"$(fd --type f "lombok-.*\d+.jar\$" "$(mvn-localrepopath)" \
          | tr '\n' ':' | rev | cut -c2- | rev)"}"

        CLASSPATH="''${CLASSPATH:-"$(mvn-classpath):$LOMBOK_JAR"}"

        # First, delombok source to tmpdir/generated-sources
        # shellcheck disable=SC2154
        mvn-delombok "$sourcepath" --target "$tmpdir/generated-sources"

        # Second, generate javadoc with class diagrams to tmpdir/reports
        # shellcheck disable=SC2154
        javadoc \
          -classpath "$CLASSPATH" \
          --module-path "$CLASSPATH" \
          -d "$tmpdir/reports" \
          -docletpath ${pkgs.UMLDoclet}/share/umldoclet.jar -doclet nl.talsmasoftware.umldoclet.UMLDoclet \
          -sourcepath "$tmpdir/generated-sources" \
          -subpackages "$subpackages" \
          "$@"

        # shellcheck disable=SC2154
        ${lib.my.openCommand config} "$tmpdir/reports/index.html"
        '';
    };
  };
in lib.attrValues scripts
