---
name: net-claude-chain
description: Set up dedicated Claude Web and Claude Desktop on Windows using a Singapore ByteVirt VPS and a Singapore CLIProxy static residential IP. Operate the real checkout up to human payment, then deploy both launchers, startup, and IP verification. 用于部署 Claude 专用网络、新加坡出口、Edge 或 Chrome 专用窗口和桌面端自动恢复。
---

# net-claude-chain

一句「使用 net-claude-chain」开始执行。先核对已有资源及电脑环境，只采购缺的。固定使用**新加坡 ByteVirt VPS + 新加坡 CLIProxy 独享静态住宅 IP**。已经买好两项资源、尚未部署时，跳过付款并自动从零部署。部署完成交付 Windows 桌面上的 `Claude 专用网络` 文件夹。

1. 读取 [采购流程](references/workflow.md)。用浏览器操作指定商家，推进到可付款页面。需要登录、验证或实际付款时交还控制。用户说「已付」后核实到账与开通。有合格资源就直接复用。
2. 读取 [部署流程](references/deployment.md)。首次部署使用仓库脚本从 Debian 空环境安装依赖、生成服务端配置、创建开机服务，再部署 Windows 客户端和后台任务。自动安装或注册官方 Claude Desktop。网页优先使用已装的 Chrome，其次 Edge，两者都没有才安装官方 Chrome。
3. 读取 [验收流程](references/acceptance.md)。分别打开网页、桌面端和 IP 检测入口。验证实际出口、断开后的行为和恢复。检测网站为 https://ip.net.coffee/ip/。
4. 留下三个入口 `Claude 网页版`、`Claude 桌面端`、`检测出口 IP`。告诉用户入口所在位置、各项实测和需要其登录的界面。

Agent 执行命令和配置。需要用户操作时，一次说明当前位置和要点，收到控制权后继续。保留用户原有 VPN、默认浏览器和日常浏览器资料。独享浏览器指独立资料目录和固定代理。需要人为登录 Claude 时保留界面，用户在官方界面登录。只对已完成的测试报告通过。
