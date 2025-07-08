{pkgs, set}:
let
  enabled = set true [
    "@textlint-ja/no-synonyms"
    "no-mixed-zenkaku-and-hankaku-alphabet"
    "ja-no-abusage"
    "prefer-tari-tari"
    "@textlint-ja/textlint-rule-no-dropping-i"
    "@textlint-ja/textlint-rule-no-insert-re" # Too slow: 900msec
    "abbr-within-parentheses"
    "ja-overlooked-typo"
  ];
  disableJTF = set false [
    # default
    "2.1.2.漢字"
    "2.1.5.カタカナ"
    "2.1.6.カタカナの長音"
    "3.1.1.全角文字と半角文字の間"
    # non-default
    "4.2.1.感嘆符(！)"
    "4.2.2.疑問符(？)"
    "4.2.7.コロン(：)"
    "4.3.1.丸かっこ（）"
    "4.3.2.大かっこ［］"
  ];

  prhRulesSrcRoot = pkgs.fetchFromGitHub {
    owner = "prh";
    repo = "rules";
    rev = "711e00793d9d69eeda04d68a796b6d9afb6d5748";
    sha256 = "sha256-iyc+/CrJSaMyJTHYtvtsl1B03F24Issqyd5xWooefoo=";
  };
  prhSmartHRRuleSrc = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/mkmn/textlint-rule-preset-smarthr/697d65350250d7658f7d08926b0763172640e635/dict/prh-idiomatic-usage.yml";
    hash = "sha256-ArHAeErY26SnqMHjb1zHS/cX5NQPkyZBmdC7/96LEls=";
  };
in {
  rules = enabled // {
    preset-japanese = {
      sentence-length = {
        max = 90;
      };
      max-ten = {
        max = 4;
      };
      no-doubled-joshi = {
        min_interval = 1;
        strict = false;
        allow = [
          "も"
          "や"
          "か"
        ];
        separatorChars = [
          "、"
          "。"
          "?"
          "!"
          "？"
          "！"
          "「"
          "」"
          "“"
          "”"
        ];
      };
      no-mix-dearu-desumasu = {
        strict = false;
      };
    };

    preset-ja-technical-writing = {
      sentence-length = false;
      max-ten = false;
      ja-no-mixed-period = {
        periodMark = "。";
        forceAppendPeriod = true;
      };
      no-exclamation-question-mark = {
        allowHalfWidthExclamation = false;
        allowFullWidthExclamation = false;
        allowHalfWidthQuestion = true;
        allowFullWidthQuestion = false;
      };
    };

    "preset-jtf-style" = disableJTF;

    preset-ja-spacing = {
      ja-space-between-half-and-full-width = {
        space = "always";
        exceptPunctuation = true;
      };
      ja-space-after-exclamation = false;
      ja-space-after-question = false;
      ja-space-around-link = true;
      ja-space-around-code = true;
    };

    prh = {
      rulePaths = [
        # "${prhRulesSrcRoot}/media/WEB+DB_PRESS.yml" # is included in textlint-rule-spellcheck-tech-word.
        "${prhRulesSrcRoot}/media/techbooster.yml"
        "${prhSmartHRRuleSrc}"
      ];
    };

    # The attribute name of proofdict is not by default: "@proofdict/proofdict"
    # Because install procedure is not different from standard one.
    proofdict = {
      dicts = [
        { dictURL = "https://azu.github.io/proof-dictionary/"; }
      ];
    };
  };
}
