---
name: net-claude-chain
description: Open Singapore ByteVirt and CLIProxy checkout for human payment, then deploy the Windows background proxy. Check Claude Desktop, install or repair the official app when needed, preserve local work, and create shortcuts for manual use. 用于新加坡 Claude 专用网络、付款后部署和桌面端安装修复。
---

# net-claude-chain

收到「使用 net-claude-chain」后直接执行。固定使用**新加坡 ByteVirt VPS + 新加坡 CLIProxy 独享静态住宅 IP**。先核对已有资源，只处理缺少的项目。两项资源都已开通时直接部署。

1. 按[部署流程](references/deployment.md)只读盘点本机的 Claude 桌面端及 Claude Code。
2. 读[采购流程](references/workflow.md)。有采购需求时，直接用浏览器打开商家、选品并走到用户能付款的页面。把付款交给用户，等到账且开通后继续。用户交还浏览器控制后恢复核对同一笔订单。
3. 资源开通后用仓库脚本部署 VPS 和 Windows。正常的桌面版直接复用，缺失时安装，有损坏时先备份再修复。确需卸载重装时先保护本地项目。网页版优先使用已装的 Chrome，其次 Edge，两者都没有才安装 Chrome。
4. 读[验收流程](references/acceptance.md)。后台验证代理和出口，在 Windows 桌面的 **Claude 专用网络** 文件夹交付 **Claude 网页版**、**Claude 桌面端**和 **检测出口 IP** 三个快捷方式。用户需要时自行打开，关闭后保持关闭。

需要登录、验证码或本机授权时，只把该操作交给用户，完成后继续同一流程。只有专用代理开机启动并在后台恢复。部署、登录 Windows 和代理恢复时均不启动 Claude 网页、桌面端或检测页。保留用户已有 VPN、默认浏览器和日常浏览器资料。交付时报告实际安装、验证及仍待处理的项。
