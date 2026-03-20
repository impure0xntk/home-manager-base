{ config, pkgs, lib, ... }:
{
  config = {
    my.testOption = "test-value";
  };

  # Assert that the option is set correctly.
  assert config.my.testOption == "test-value";
}
