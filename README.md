# mac-daily-credits

一个用于 **macOS** 的每日额度领取脚本，支持 **Qoder、WorkBuddy、Trae 国内版**。读取本机客户端已有的登录状态，自动检查并领取可用额度，无需重复登录。

## 使用要求

- macOS，已登录桌面会话。
- Node.js 20 或更高版本（可用 `node -v` 检查）。
- 已安装并登录需要签到的客户端。
- 不要使用 `sudo` 运行。

## 一行安装每日自动签到

复制以下命令到终端执行：

```bash
curl -fsSL https://raw.githubusercontent.com/NoName4Me/mac-daily-credits/master/mac-credits.sh -o "$HOME/Downloads/mac-credits.sh" && bash "$HOME/Downloads/mac-credits.sh" --install
```

脚本会下载到 `~/Downloads/mac-credits.sh`，并安装 macOS `launchd` 定时任务：

- **默认每天 10:10 签到**，按 **Mac 系统本地时区**计算。
- 安装/登录加载任务时也可能立即执行一次。
- 定时任务运行时不必保持终端打开，但 Mac 需要处于可执行任务的状态。

如果只想**立即签到一次、不安装定时任务**，也可以执行：

```bash
curl -fsSL https://raw.githubusercontent.com/NoName4Me/mac-daily-credits/master/mac-credits.sh | bash
```

> 以上命令会执行 GitHub 上的脚本。建议先查看 [脚本源码](mac-credits.sh)，确认后再运行。

## 常用命令

下载脚本后，可用以下命令操作：

```bash
# 只检查签到状态，不实际领取
bash ~/Downloads/mac-credits.sh --check

# 立即领取
bash ~/Downloads/mac-credits.sh

# 查看诊断信息（不领取）
bash ~/Downloads/mac-credits.sh --diagnose

# 设置每天自动签到，默认 10:10
bash ~/Downloads/mac-credits.sh --install

# 指定每天签到时间（24 小时制，示例 11:30）
bash ~/Downloads/mac-credits.sh --install --time 11:30

# 查看定时任务
bash ~/Downloads/mac-credits.sh --status

# 取消自动签到
bash ~/Downloads/mac-credits.sh --uninstall
```

**时间说明：** `--time HH:MM` 使用 Mac 的系统时区。Qoder 每日额度通常在**北京时间 10:00**刷新；如果 Mac 使用北京时间，默认的 10:10 即可。如果 Mac 使用日本时间，请设置为 `--time 11:10` 或更晚。重复运行 `--install` 会更新定时配置；不传 `--time` 时恢复默认 10:10。

## 查看日志

```bash
tail -n 100 ~/Library/Logs/mac-credits/run.log
tail -n 100 ~/Library/Logs/mac-credits/error.log
```

定时脚本存放于 `~/.local/bin/mac-credits.sh`。更新下载的脚本后，重新执行 `--install` 即可更新定时任务使用的版本。

## 说明

- 只支持三个应用的**国内版**，不支持国际版。
- 依赖各客户端的本地登录状态与非公开接口；客户端或服务端变更可能影响可用性。
- 脚本不主动将 Token 保存到新的文件中；诊断日志可能包含本机文件路径，公开前请注意脱敏。
- 这是非官方工具，与上述应用的开发公司无关。

## 开源协议

[MIT License](LICENSE)。协议实现参考了 [CreditDaddy](https://github.com/techysy/CreditDaddy) 和 [workbuddy-auto-signin](https://github.com/88lin/workbuddy-auto-signin)；第三方版权声明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
