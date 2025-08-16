{ pkgs, lib, additionalRc ? {}, gramma ? { enable = false; }, }:
let
  set =
    value: list:
    let
      kV = builtins.map (item: (lib.nameValuePair item value)) list;
    in
    builtins.listToAttrs kV;
  rc = {
    filters = {
      comments = true;
    };
    rules = set true [
      # Common
      "use-si-units"
      "date-weekday-mismatch"
      "@textlint-rule/no-invalid-control-character"
      "no-zero-width-spaces"
      "doubled-spaces"
      "no-curly-quotes"
      "@textlint-rule/no-unmatched-pair"

      # Markdown
      "period-in-list-item"
      "no-bold-paragraph"
    ] // {
      # The attribute name of proofdict is not by default: "@proofdict/proofdict"
      # Because install procedure is not different from standard one.
      proofdict = {
        autoUpdateInterval = 12 * 60 * 60 * 1000; # default 60 * 1000 = 60 sec
      };

      "@textlint-rule/gramma" = lib.optionalAttrs gramma.enable {
        api_url = gramma.apiUrl;
        language = "auto";
      };
      "@kmuto/kmu-termcheck" = { # Too slow: 400msec
        severity = "info"; # too many false positive
      };
    };
  };
  rcJa = import ./ja { inherit pkgs set; };
  rcEn = import ./en { inherit set; };

  rcLangs = lib.recursiveUpdate rcJa rcEn;
  rcAll = lib.recursiveUpdate rc rcLangs;
in
builtins.toJSON (lib.recursiveUpdate rcAll additionalRc)
