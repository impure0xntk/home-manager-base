{ set }:
let
in
{
  rules = {
    write-good = {
      passive = false;
    };
    alex = {
      allow = [ ];
    };
    max-comma = {
      max = 4;
    };
    stop-words = {
      defaultWords = true;
    };
    terminology = {
      defaultTerms = true;
    };
    en-max-word-count = {
      max = 50;
    };
    unexpanded-acronym = {
      min_acronym_len = 3;
    } ;
    no-start-duplicated-conjunction = {
      interval = 2;
    };
    apostrophe = true;
    en-capitalization = true;
    sentence-length = {
      max = 100;
      skipPatterns = [
        "/\".*?\"/"
      ];
    };
    "@textlint-rule/gramma" = {
      api_url = "http://localhost:18181/v2/check";
      language = "en-US";
    };
  };
}
