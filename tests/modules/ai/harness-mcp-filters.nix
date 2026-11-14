{ config, lib, ... }:

let
  compressedArgs = config.my.home.ai.harness.mcpServers.compressed-tools.args;
in
{
  config = {
    my.home.ai.harness = {
      enable = true;
      codingAgentTools = {
        ctx.mcpServer.excludeTools = [
          "graph_stats"
          "graph_query"
          "graph_stats"
        ];
      };
    };

    assertions = [
      {
        assertion = lib.hasInfix "--exclude-tools graph_query,graph_stats" compressedArgs;
        message = "Excluded backend tool names must be deduplicated, sorted and merged into one --exclude-tools flag.";
      }
    ];
  };
}
