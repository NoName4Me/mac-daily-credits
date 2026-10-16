#!/usr/bin/env bash
# 只测试 launchd 任务的生成，不连接签到服务或读取真实客户端凭据。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

export HOME="$TEST_DIR/home"
export NODE_BIN="$(command -v node)"
mkdir -p "$HOME" "$TEST_DIR/bin"
cat > "$TEST_DIR/bin/launchctl" <<'MOCK'
#!/bin/sh
exit 0
MOCK
chmod +x "$TEST_DIR/bin/launchctl"
export PATH="$TEST_DIR/bin:$PATH"

PLIST="$HOME/Library/LaunchAgents/com.local.mac-credits.plist"

assert_schedule() {
  local hour="$1" minute="$2"
  grep -Fq "<key>Hour</key><integer>$hour</integer>" "$PLIST"
  grep -Fq "<key>Minute</key><integer>$minute</integer>" "$PLIST"
}

bash "$ROOT/mac-credits.sh" --install
assert_schedule 10 10

bash "$ROOT/mac-credits.sh" --install --time 07:05
assert_schedule 7 5

# 不合法的时间不能覆盖已安装的定时任务。
for time in 24:00 10:60 9:10 abc -1:30; do
  if bash "$ROOT/mac-credits.sh" --install --time "$time" >/dev/null 2>&1; then
    echo "错误：非法时间 $time 被接受" >&2
    exit 1
  fi
  assert_schedule 7 5
done

if bash "$ROOT/mac-credits.sh" --install --time >/dev/null 2>&1; then
  echo "错误：缺少时间值仍安装成功" >&2
  exit 1
fi
if bash "$ROOT/mac-credits.sh" --install --unexpected 11:30 >/dev/null 2>&1; then
  echo "错误：未知选项被接受" >&2
  exit 1
fi
assert_schedule 7 5

bash "$ROOT/mac-credits.sh" --uninstall
test ! -f "$PLIST"
echo "定时任务参数测试通过"
