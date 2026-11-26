---
name: net-claude-chain
description: Open the Singapore ByteVirt and CLIProxy websites, prepare human checkout, and resume automatically after payment. Deploy and maintain the Windows background proxy, download official Claude Desktop when needed, and create shortcuts for manual use. 用于新加坡 Claude 专用网络、付款后自动部署和桌面端安装。
---

# net-claude-chain

收到「使用 net-claude-chain」后直接执行。固定使用**新加坡 ByteVirt VPS + 新加坡 CLIProxy 独享静态住宅 IP**。先核对已有资源，只处理缺少的项目。两项资源都已开通时直接部署。

1. 读[采购流程](references/workflow.md)。Agent 自动打开所需商家的页面，核对并操作到能付款的页面。付款由用户操作。订单状态可读时继续检查到账和开通；需要交接浏览器时，用户交还控制后恢复检查，无需再发「已付」。
2. 读[部署流程](references/deployment.md)。资源开通后立即用仓库脚本部署 VPS 和 Windows。电脑缺少 Claude Desktop 时自动下载、验签并安装官方版本。网页版优先使用已装的 Chrome，其次 Edge，两者都没有才安装 Chrome。
3. 读[验收流程](references/acceptance.md)。后台验证代理和出口，在 Windows 桌面的 **Claude 专用网络** 文件夹交付 **Claude 网页版**、**Claude 桌面端**和 **检测出口 IP** 三个快捷方式。用户需要时自行打开，关闭后保持关闭。

需要登录、验证码或本机授权时，只把该操作交给用户，完成后继续同一流程。只有专用代理开机启动并在后台恢复。部署、登录 Windows 和代理恢复时均不启动 Claude 网页、桌面端或检测页。保留用户已有 VPN、默认浏览器和日常浏览器资料。交付时报告实际安装、验证及仍待处理的项。
