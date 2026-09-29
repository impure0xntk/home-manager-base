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
        zg.mcpServer.includeTools = [ "zvec_grep_search" ];
      };
    };

    assertions = [
      {
        assertion = lib.hasInfix "--exclude-tools graph_query,graph_stats" compressedArgs;
        message = "Excluded backend tool names must be deduplicated, sorted and merged into one --exclude-tools flag.";
      }
      {
        assertion = lib.hasInfix "--include-tools zvec_grep_search" compressedArgs;
        message = "Included backend tool names must reach mcp-compressor as --include-tools.";
      }
    ];
  };
}
