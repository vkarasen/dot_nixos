# Dendritic aspect: pi MCP server aggregation (home-manager class).
#
# Single writer of ~/.pi/agent/mcp.json — pi's built-in MCP configuration,
# read natively since 0.99.0. Other aspects contribute servers additively
# via my.pi.mcpServers instead of writing the file themselves. home.file's
# `text` option is types.lines, so two direct writers would concatenate the
# JSON (corrupting it) rather than merge — keeping exactly one aggregation
# point here avoids that footgun.
{...}: {
  flake.modules.homeManager.pi-mcp = {config, ...}: {
    home.file.".pi/agent/mcp.json".text = builtins.toJSON {
      mcpServers = config.my.pi.mcpServers;
    };
  };
}
