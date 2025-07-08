{config, pkgs, home, ...}:
let
netsurfWithFrameBuffer = pkgs.netsurf.browser.override { uilib = "framebuffer"; };
in {
  home.packages = [ netsurfWithFrameBuffer ];
}