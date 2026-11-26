# net-claude-chain

在 Windows 上用 Agent 部署 Claude 专用网络，固定使用新加坡 ByteVirt VPS 和新加坡 CLIProxy 独享静态住宅 IP。

## 用法

把下面这一句发给能操作浏览器和本机的 Codex Agent。

> 请从 https://github.com/h296025733-sys/net-claude-chain 下载安装并使用 net-claude-chain。

Agent 检查已有资源，自动打开所需商家的付款页。你在商家页面付款，浏览器如已交接，付完点「交还控制」。Agent 确认开通后自动部署 VPS 和 Windows，下载并安装缺少的 Claude 桌面端，并在 Windows 桌面的 **Claude 专用网络** 文件夹创建三个快捷方式。专用代理开机后在后台运行，三个入口都由用户按需打开，关闭后保持关闭。

| 入口 | 打开什么 |
| --- | --- |
| Claude 网页版 | 用专用 Chrome 或 Edge 打开 Claude 网页 |
| Claude 桌面端 | 打开已配置的官方 Claude 应用 |
| 检测出口 IP | 用专用浏览器打开 Net.Coffee |

第一次使用 Claude 时，在打开的官方界面内登录。脚本及流程以 [SKILL.md](SKILL.md) 为入口。
