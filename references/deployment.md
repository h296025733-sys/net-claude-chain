# 从已购买的设备和住宅 IP 开始部署

Agent 执行以下步骤。两个资源已开通时跳过购买。若 VPS 没有配置过，按首次部署执行。只有手头已经有经过验证的完整链路时，才复用它。

## 先检查本机 Claude

在当前交互 Windows 用户下点载 `scripts/windows-client-common.ps1` 和 `scripts/claude-desktop-maintenance.ps1`。调用 `Get-ClaudeDesktopState`，查看 `State`、包版本和是否有旧版桌面端或独立 Claude Code CLI。此步骤只读，可在等待资源开通前完成。

- `Healthy` 表示官方 MSIX 注册状态正常且程序文件存在。复用它并配置专用快捷方式。
- `Missing` 表示当前用户没有官方 MSIX。安装前核对已存在的旧版数据，下载并验签官方 MSIX，安装后复查。旧版桌面程序和独立 CLI 按各自原有的安装方式管理。
- `NeedsRepair` 表示注册或程序文件异常。先让用户保存工作并退出 Claude。安装脚本先备份本地数据，再尝试用验签后的官方包原位修复。若包状态正常，但已实测应用本身无法正常启动，使用 `-RepairClaudeDesktop` 显式尝试原位修复。

安装前的备份保存在 `%LOCALAPPDATA%\NetClaudeChain\ClaudeBackups`，包含已有的桌面端数据、Claude Code 本地设置及会话、`CLAUDE_CONFIG_DIR` 指向的配置和通过 `-ClaudeProjectPath` 指定的项目目录。`sources.json` 记录原始位置。普通项目文件夹保持原位。备份可能包含会话和账号资料，留在当前电脑。

原位修复失败后，先确认可读取的备份。对只存在 Cowork 内部的项目，让用户先把文件导出到普通文件夹，打开导出的副本核对。若原件和可用副本都无法打开，暂停卸载。确认可以卸载后才重跑安装脚本并加 `-ReinstallClaudeDesktop`，它会在备份成功后仅移除当前用户的官方 MSIX，再安装已验签的包。重装后检查项目副本、应用状态和快捷方式。账号登录由用户在官方界面完成。

## 首次部署

1. 通过商家后台确认资源都在新加坡，登录 ByteVirt 的 Debian 11 或 12。准备 SSH、Windows 管理员权限和当前交互 Windows 用户。在 CLIProxy 获取 SOCKS5 连接地址、端口和账密。通过受保护的代理配置测试 `https://api.ipify.org`，记录真实、固定的住宅出口 IPv4。代理连接地址与最终出口分别记录。若商家提供域名，将 SOCKS5 主机名解析为经验证的 IPv4。
2. 先在 Windows 执行 `scripts/download-windows-xray.ps1 -Destination <独立临时目录>`。脚本自动从 Xray 官方 GitHub 获取 Windows 发行包，并核对 SHA-256。返回的 `xray.exe` 路径用于后面的本机安装。
3. 在 Debian 准备受限的临时目录，用 SCP 或已授权的 SSH 工具上传 `scripts/deploy-singapore-server.py`。在同目录写入权限 0600 的 JSON，字段为 `proxy_ip`、`proxy_port`、`username`、`password`。使用 root 或 sudo。若 `python3` 缺失，用 `apt-get update` 和 `apt-get install -y python3 ca-certificates` 安装后继续。执行示例见下方。脚本自行安装缺失的 nftables，下载并校验官方 Linux Xray，创建独立服务、凭据、出站限制和 Windows 客户端配置。已在跑的服务继续使用原配置。
4. 新服务默认监听 443。先通过 `ss` 检查端口和商家后台的入站规则，遇到占用使用允许且空闲的端口并传 `--listen`。代理端口默认监听 Windows 环回地址 10810。遇到本机冲突时用 `--local-port` 选择空闲端口，并在后续传相同端口。保存经验证的 VPS SSH 主机密钥。临时凭据上传后检查 0600，脚本读完即清理临时输入。
5. SCP 取回 `/etc/net-claude-chain/client.json` 至已保护的临时文件。它含连接凭据。先用上面下载的 Windows Xray临时启动 `xray.exe run -c <客户端配置>`，经此环回代理访问 `https://api.ipify.org`，核对与住宅出口一致。确认后停止测试进程，执行 `systemctl stop net-claude-chain-safety.timer` 和 `systemctl enable net-claude-chain-guard.service net-claude-chain.service`。安全定时器为 180 秒。超时后核查服务，重新启动这两项服务，再充分验证。
6. 在当前 Windows 用户的管理员 PowerShell 执行 `scripts/install-windows-client.ps1`，带上新客户端配置、Windows Xray 路径、VPS 地址、住宅出口及本机端口。脚本配置开机代理、物理网卡路由、应用出站限制和三个快捷方式，按上文复用、安装或修复 [Claude Desktop 官方 MSIX](https://support.claude.com/en/articles/12622703-deploy-claude-desktop-for-windows)。两种支持的浏览器都缺失时装官方 Chrome。需要用专用桌面端时，先保存工作并退出普通方式打开的 Claude，再双击专用快捷方式。
7. 安装器结束后，Agent 按 [验收步骤](acceptance.md) 在后台检查代理出口和快捷方式。应用窗口由用户按需打开。记录本机配置路径和服务到期时间。清理临时凭据文件。

```bash
sudo python3 deploy-singapore-server.py --vps-ip "$VPS_IP" --credentials "$CREDENTIALS_FILE"
```

```powershell
$xray = & .\scripts\download-windows-xray.ps1 -Destination $temporaryFolder
& .\scripts\install-windows-client.ps1 -VpsIp $vpsIp -ExpectedExit $exitIp -ProxyPort $httpPort -XrayExecutable $xray -ClientConfig $clientConfig
```

## 已有可用链路

完整链路已通过出口和断开测试时，保留已有代理。调用 Windows 安装器只传 `-VpsIp`、`-ExpectedExit`、`-ProxyPort`，让 Agent 安装或补齐使用入口、路由维护和桌面端任务。验收已有代理的开机启动与恢复能力。

已有部署只需要更新快捷方式时，在当前用户的管理员 PowerShell 执行 `scripts/update-windows-launchers.ps1`。它移除旧版桌面自动启动任务并更新快捷方式，保留运行中的代理和现有配置。

## 运行位置

自动化配置默认放在 `%ProgramData%\NetClaudeChain`。浏览器资料在 `%LOCALAPPDATA%\NetClaudeChain\Profiles`，网页不继承普通 Chrome 或 Edge 的用户资料。专用代理随 Windows 开机启动并在后台恢复。Claude Desktop 和专用浏览器均通过桌面快捷方式按需启动。如果 VPN 强制接管或阻断物理路由，保持 VPN 原有配置并报告实测影响。回滚只动本次创建的服务、任务和规则。
