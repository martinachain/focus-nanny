#!/usr/bin/env bash
#
# focus-nanny 安装脚本
# 自动完成所有「程序能做」的步骤；macOS 的「辅助功能」授权必须本人手动开启
# （任何程序都无法给自己授权——这是系统安全机制），脚本最后会提示。
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HS_CONFIG="$HOME/.hammerspoon/init.lua"
TASK_FILE="$HOME/Desktop/今日任务.txt"

echo "focus-nanny 安装开始..."
echo ""

# 1. 确保 Hammerspoon 已安装
if [ -d "/Applications/Hammerspoon.app" ]; then
    echo "[OK] Hammerspoon 已安装"
elif command -v brew >/dev/null 2>&1; then
    echo "[..] 用 Homebrew 安装 Hammerspoon..."
    brew install --cask hammerspoon
    echo "[OK] Hammerspoon 安装完成"
else
    echo "[!!] 未检测到 Hammerspoon，也没找到 Homebrew。"
    echo "     请先装 Homebrew（https://brew.sh），或手动下载 Hammerspoon"
    echo "     （https://www.hammerspoon.org）拖进「应用程序」，再重跑本脚本。"
    exit 1
fi

# 2. 部署 init.lua（已有配置先备份，不覆盖别人的）
mkdir -p "$HOME/.hammerspoon"
if [ -f "$HS_CONFIG" ]; then
    BACKUP="$HS_CONFIG.backup.$(date +%Y%m%d%H%M%S)"
    cp "$HS_CONFIG" "$BACKUP"
    echo "[!!] 已存在 ~/.hammerspoon/init.lua，已备份到：$BACKUP"
fi
cp "$REPO_DIR/init.lua" "$HS_CONFIG"
echo "[OK] init.lua 已就位（~/.hammerspoon/init.lua）"

# 3. 建今日任务文件（已存在则不覆盖）
if [ -f "$TASK_FILE" ]; then
    echo "[OK] 今日任务文件已存在，跳过：$TASK_FILE"
else
    printf '%s\n' "写完今天最重要的事" "回复消息" "运动 30 分钟" > "$TASK_FILE"
    echo "[OK] 已创建任务文件：$TASK_FILE（每行一条，第一行最重要，可随时编辑）"
fi

# 4. 启动 / 重启 Hammerspoon 加载配置
pkill -x Hammerspoon 2>/dev/null || true
sleep 1
open "/Applications/Hammerspoon.app"
echo "[OK] Hammerspoon 已启动"

# 5. 提示必须手动的最后一步
cat <<'TIP'

------------------------------------------------------
还差最后一步，必须本人操作（程序无法代劳）：

   给 Hammerspoon 开「辅助功能」权限：
   系统设置 > 隐私与安全性 > 辅助功能 > 打开 Hammerspoon

   focus-nanny 靠它读窗口标题判断摸鱼，
   不授权的话提醒卡片永远不会弹出来。

   授权后：点菜单栏锤子图标 > Reload Config，或重跑本脚本。
------------------------------------------------------

装好后试一下：切到 X / 小红书 / YouTube / B 站，
屏幕右上角会弹出一张大红卡片提醒你别摸鱼。
TIP
