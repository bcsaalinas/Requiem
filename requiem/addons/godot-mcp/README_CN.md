# Godot MCP Bridge — Editor Plugin

[English](README.md) | [中文](README_CN.md)

> Godot 编辑器插件 —— [Godot MCP Bridge](https://github.com/letsagents/godot-mcp) 的 editor 侧。

本插件开一个 TCP bridge,让 [MCP server](@letsagents/godot-mcp) 连进来,把 Godot 内置 debug 协议(错误 / 场景树 / 节点属性 / 截图)暴露给 AI 客户端。

> 📦 本插件**只是 editor 侧**。**MCP server** 要另外装(`npm i -g @letsagents/godot-mcp`),客户端配置见 [server README](https://github.com/letsagents/godot-mcp/blob/main/mcp-server/README.md)。

## 启用

1. 本目录放到 Godot 项目的 `addons/`(AssetLib 安装或手动解压 zip 都行)。
2. **Project Settings → Plugins** → 勾选 **Godot MCP Bridge**。

> autoload 由插件**自动注册**,无需手动改 `project.godot`。

## 配置 bridge 端口(可选)

插件默认在 `6510` 监听 TCP。多 editor 并行时,每个项目设不同端口 —— 编辑 `project.godot`:

```ini
[godot_mcp]
bridge_port=6511
```

server 侧的 `GODOT_MCP_BRIDGE_PORT` 环境变量要和这里一致。

## 下一步

- 装 server + 配置 MCP 客户端 → [server README](https://github.com/letsagents/godot-mcp/blob/main/mcp-server/README.md)
- 完整工具列表 / 架构 / 踩坑 → [主仓库文档](https://github.com/letsagents/godot-mcp#readme)

## License

MIT © LuoHan
