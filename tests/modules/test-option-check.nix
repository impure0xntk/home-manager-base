{ config, pkgs, lib, ... }:
{
  config = {
    my.testOption = "test-value";
    assertions = [
      {
        assertion = config.my.testOption == "test-value";
        message = "my.testOption must be set to test-value.";
      }
    ];
  };
}
