# rtk refuses to run its filters at all when config.toml fails to deserialize:
# the sqlite recall store goes inactive, every lossy filter falls back to printing
# the full raw output, and `rtk gain` then reports 0% savings. These assertions pin
# the schema fields serde requires plus the noise classes the nix filter targets.

{ config, lib, ... }:

let
  rtkRoot = ../../../modules/ai/harness/tools/rtk;
  rtkConfig = rtkRoot + "/config.toml";
  rtkFilters = rtkRoot + "/filters/nix.toml";
in
{
  config = {
    my.home.ai.harness.enable = true;

    assertions = [
      {
        assertion = lib.hasAttr "rtk/config.toml" config.xdg.configFile
          && lib.hasAttr "rtk/filters.toml" config.xdg.configFile;
        message = "The rtk tool must deploy both its config.toml and its filters.toml, otherwise no filter can ever match.";
      }
      {
        assertion = lib.hasInfix "max_width" (builtins.readFile rtkConfig);
        message = "rtk config.toml must set display.max_width; a missing field aborts deserialization and silently disables every filter.";
      }
      {
        assertion = lib.hasInfix "[telemetry]\nenabled" (builtins.readFile rtkConfig);
        message = "rtk config.toml must use the telemetry `enabled` key; `enable` is not a field of TelemetryConfig.";
      }
      {
        assertion = lib.hasInfix "[tracking]\nenabled" (builtins.readFile rtkConfig)
          && lib.hasInfix "history_days" (builtins.readFile rtkConfig);
        message = "rtk config.toml must set both tracking.enabled and tracking.history_days; both are mandatory fields of TrackingConfig.";
      }
      {
        assertion = lib.hasInfix "^evaluating '" (builtins.readFile rtkFilters);
        message = "The nix filter must strip `evaluating '...'` progress, the dominant output of `nix eval` and `nix search`.";
      }
      {
        assertion = lib.hasInfix "tail_lines" (builtins.readFile rtkFilters);
        message = "The nix filter must keep a tail; nix prints the value or the error after the progress log, so a head-only cap would drop the answer.";
      }
    ];
  };
}
