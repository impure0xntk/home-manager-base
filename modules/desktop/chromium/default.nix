{ config, pkgs, lib, ... }:
let
  cfg = config.my.home.desktop.chromium;
in {
  options.my.home.desktop.chromium.enable = lib.mkEnableOption "Whether to enable chromium browser.";

  config = lib.mkIf cfg.enable {
    programs.chromium = {
      enable = true;
      extensions = [
        { id = "bgnkhhnnamicmpeenaelnjfhikgbkllg"; } # AdGuard
        { id = "nngceckbapebfimnlniiiahkandclblb"; } # Bitwarden
        { id = "eimadpbcbfnmbkopoojfekhnkhdbieeh"; } # Dark Reader
        { id = "jlgkpaicikihijadgifklkbpdajbkhjo"; } # crxMouth
        { id = "ldpochfccmkkmhdbclfhpagapcfdljkj"; } # Decentraleyes
        { id = "ponfpcnoihfmfllpaingbgckeeldkhle"; } # Enhancer for Youtube
        { id = "fihnjjcciajhdojfnbdddfaoknhalnja"; } # I don't care about cookies
        { id = "cedcejfiniojnlhlfhcppenochinijfo"; } # Search Result Preview
        { id = "oklfoejikkmejobodofaimigojomlfim"; } # Shut Up: Comment Blocker
        { id = "mnjggcdmjocbbbhaepdhchncahnbgone"; } # SponcerBlock for Youtube
        { id = "dbepggeogbaibhgnhhndojpepiihcmeb"; } # Vimium
      ];
    };
  };
}
