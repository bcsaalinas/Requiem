# Godot MCP Bridge — Editor Plugin

[English](README.md) | [中文](README_CN.md)

> The Godot editor plugin — the editor-side half of [Godot MCP Bridge](https://github.com/letsagents/godot-mcp).

This plugin opens a TCP bridge that the [MCP server](@letsagents/godot-mcp) connects to, exposing Godot's built-in debug protocol (errors / scene tree / node properties / screenshots) to AI clients.

> 📦 This plugin is **editor-side only**. The **MCP server** is a separate install (`npm i -g @letsagents/godot-mcp`); client configuration is in the [server README](https://github.com/letsagents/godot-mcp/blob/main/mcp-server/README.md).

## Enable

1. Place this directory (`addons/godot-mcp/`) into your Godot project's `addons/` (via AssetLib install or manual zip extract).
2. **Project Settings → Plugins** → enable **Godot MCP Bridge**.

> The autoload is **registered automatically** by the plugin — no need to edit `project.godot` by hand.

## Bridge port (optional)

The plugin listens on TCP port `6510` by default. To run multiple editors at once, give each project a different port — edit `project.godot`:

```ini
[godot_mcp]
bridge_port=6511
```

The server's `GODOT_MCP_BRIDGE_PORT` environment variable must match this.

## Next steps

- Install the server + configure your MCP client → [server README](https://github.com/letsagents/godot-mcp/blob/main/mcp-server/README.md)
- Full tool list / architecture / pitfalls → [main repo docs](https://github.com/letsagents/godot-mcp#readme)

## License

MIT © LuoHan
