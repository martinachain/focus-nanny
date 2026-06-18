# focus-nanny 🐶 专注监工小狗

> A tiny macOS focus guard built with [Hammerspoon](https://www.hammerspoon.org/). It stays hidden while you work, and the moment you drift to a time-wasting site, a big red card pops up in the corner showing your to-do list and a "slacking for X min" timer.

一个 macOS 桌面小工具，用 [Hammerspoon](https://www.hammerspoon.org/) 写成，几十行 Lua。**专注干活时它隐身不挡你，一碰摸鱼网站才现身。**

它会：
1. **专注时隐身**：你正经干活时，屏幕上看不到它，不挡视线、不分心。
2. **后台盯梢**：每 2 秒检查一次你在干嘛。一旦你跑去刷 X / 推特 / 小红书 / YouTube / B 站，屏幕角落 **立刻弹出一张大红卡片**，显示你的今日任务 +「摸鱼中 X 分Y秒」并开始计时。
3. **切回干活立刻消失**：红卡片自动隐藏，摸鱼计时归零。
4. **摸久了点名催你**：连续摸鱼超过设定时间（默认 5 分钟），弹一条系统通知念出你今日任务的第一行，之后每隔 5 分钟再催一次（不会狂弹）。

> 这是个简单的 MVP，先跑起来看顺不顺手，再决定要不要加功能。

---

## 一、显示逻辑（卡片什么时候出现/消失）

- **专注时隐身**：正经干活时卡片 **完全隐藏**，屏幕上看不到，不挡活、不分心。
- **一碰摸鱼立刻现身**：只要前台窗口标题命中摸鱼名单，角落（默认右上角）**立刻弹出大红卡片**，显示今日任务 + 「⚠️ 摸鱼中 X 分Y秒 · 今天要干活！」并即时计时。**不用等 5 分钟。**
- **切回干活立刻消失**：一离开摸鱼网站，红卡片自动隐藏，计时和提醒节流全部归零。
- **摸够阈值才弹系统通知**：摸鱼连续累计满 `ALERT_THRESHOLD`（默认 300 秒 = 5 分钟）后，弹一条 macOS 系统通知点名今日任务第一行；之后按 `ALERT_INTERVAL`（默认 300 秒）节流，不狂弹。
- **暂停时**：按 ⌘⌥⌃P 暂停后，卡片隐藏、不盯、不计时、不弹（见第五节）。

> 小结：红卡片 = 即时反馈（一碰摸鱼就弹、切回就消失）；系统通知 = 延时惩罚（摸够 5 分钟才弹）。

---

## 二、它怎么判断你在摸鱼？

靠 **前台窗口标题（window title）**：每 2 秒读一次当前最前窗口的标题（`hs.window.focusedWindow():title()`），转小写后和摸鱼关键词名单 `BLOCKLIST_TITLE` 做子串匹配，命中任意一个就算摸鱼。

- **看窗口标题**：默认名单 `{ "/ x", "twitter", "小红书", "youtube", "bilibili", "哔哩" }`。例如推特页面标题形如 `(1) 主页 / X`，命中 `"/ x"`。读窗口标题而不是网址，所以对任何浏览器、任何标签页都通用。
- **看 App**（预留）：把某些 App 名加进 `BLOCKLIST_APP`，前台是它就算摸鱼（默认空）。

### 为什么不直接抓浏览器网址（URL）？

早期方案是用 AppleScript 抓 Chrome / Safari 当前标签的网址。但在作者的机器上，**Chrome 的 AppleScript 接口恒报 `count of windows = 0`，网址永远读不到**（Chrome AppleScript 的已知毛病，和环境相关）。所以改用「窗口标题」方案：标题走 **辅助功能（Accessibility）** 权限，稳定可读，且对任何浏览器通用、还少要一个权限。

> 如果你的环境抓 URL 正常，也完全可以自行改造成抓 URL 判断——这里选窗口标题是图它通用、稳定、权限少。

---

## ⚡ 快速安装（推荐，也适合丢给 AI 装）

```bash
git clone https://github.com/martinachain/focus-nanny.git
cd focus-nanny
bash install.sh
```

`install.sh` 会自动：用 Homebrew 装 Hammerspoon、把 `init.lua` 放到 `~/.hammerspoon/`（已有配置会先备份）、建一个 `~/Desktop/今日任务.txt`、启动 Hammerspoon。

**最后一步必须你本人操作**（macOS 安全机制，任何程序/AI 都无法代劳）：

> 系统设置 › 隐私与安全性 › **辅助功能** → 打开 **Hammerspoon** 开关。
> focus-nanny 靠它读窗口标题判断摸鱼，不授权红卡片不会弹。授权后点菜单栏 🔨 → Reload Config（或重跑 `install.sh`）。

> 💡 把本仓库地址丢给你的 AI（Claude Code / Cursor 等），让它执行上面三行命令也行——它能装到「就差授权」，那一步它会提醒你手动点一下。

下面是不想用脚本时的**手动安装**步骤。

---

## 三、部署（手动，第一次安装）

### 1. 装 Hammerspoon
去 https://www.hammerspoon.org/ 下载，拖进「应用程序」。

### 2. 把 init.lua 放到 Hammerspoon 配置目录
Hammerspoon 只认 `~/.hammerspoon/init.lua` 这个文件。在本仓库根目录执行：

```bash
mkdir -p ~/.hammerspoon
cp init.lua ~/.hammerspoon/init.lua
```

> ⚠️ 如果你的 `~/.hammerspoon/init.lua` 里已有别的配置，直接 `cp` 会覆盖。那种情况把本项目 init.lua 的内容 **追加** 进你已有的文件，或用 `dofile` 引入。

### 3. 建一个今日任务文件
```bash
echo "写完项目文档
回复 3 封邮件
健身 30 分钟" > ~/Desktop/今日任务.txt
```
每行一条任务，**第一行最重要**（催你的通知里会念第一行）。任务文件路径可在 `TASK_FILE` 改。

### 4. 启动 / 重载
- 打开 Hammerspoon（菜单栏会出现一个锤子图标 🔨）。
- 菜单栏锤子 → **Reload Config**，或运行时按 **⌘⌥⌃R** 重载。
- 看到屏幕中间闪过 `focus-nanny 上岗 🐶` 就成功了。

---

## 四、授权（很关键，不授权识别不了摸鱼）

macOS 默认不让程序偷看别的窗口，要手动给 Hammerspoon 权限：

**辅助功能（Accessibility）**：系统设置 → 隐私与安全性 → **辅助功能** → 打开 **Hammerspoon**。Hammerspoon 第一次跑通常会自己弹窗请求。

> 读窗口标题就靠这个权限。没给的话读不到标题、刷 X 不会被识别、红卡片永远不弹。授权后重载一次即可。本方案 **不需要「自动化（Automation）」权限**。

---

## 五、快捷键

| 快捷键 | 作用 |
|---|---|
| **⌘⌥⌃P** | **暂停 / 恢复监工**。暂停后卡片隐藏、不盯、不计时、不弹，计时清零；再按恢复。屏幕会闪提示当前状态。 |
| **⌘⌥⌃R** | **重载配置**。改完 init.lua 后按这个生效（等同菜单栏锤子 → Reload Config）。 |

---

## 六、改配置（全在 init.lua 顶部）

打开 `~/.hammerspoon/init.lua`，改完按 **⌘⌥⌃R** 重载生效。

### 6.1 行为配置

| 配置项 | 作用 | 默认值 |
|---|---|---|
| `TASK_FILE` | 今日任务文件路径 | `~/Desktop/今日任务.txt` |
| `BLOCKLIST_TITLE` | 窗口标题关键词，标题含任意一个即摸鱼 | `"/ x" / "twitter" / "小红书" / "youtube" / "bilibili" / "哔哩"` |
| `BLOCKLIST_APP` | App 名黑名单，前台是它即摸鱼 | 空 `{}` |
| `ALERT_THRESHOLD` | 连续摸鱼多少秒后【开始】弹系统通知 | `300`（5 分钟） |
| `ALERT_INTERVAL` | 弹过之后每隔多少秒再弹一次 | `300`（5 分钟） |
| `CHECK_INTERVAL` | 每几秒检查一次 | `2` |

### 6.2 外观配置（窗口大小 / 透明度 / 位置）

| 配置项 | 作用 | 默认值 | 可填什么 |
|---|---|---|---|
| `WIN_WIDTH` | 窗口宽度（像素）= 卡片大小，越大越显眼 | `260` | 任意正整数，如 `190`（更小）/ `320`（更大） |
| `FONT_TITLE` | 「🎯 今日任务」标题字号 | `15` | 任意正整数 |
| `FONT_TASK` | 任务正文字号 | `13` | 任意正整数 |
| `FONT_STATUS` | 底部状态行字号 | `13` | 任意正整数 |
| `OPACITY` | 透明度，0=全透明 ~ 1=不透明 | `0.78` | `0`~`1` 小数（摸鱼红态会自动再加一点不透明度，更醒目） |
| `POSITION` | 卡片贴哪个屏幕角 | `"topright"` | `"topright"` / `"topleft"` / `"bottomright"` / `"bottomleft"`，**带引号** |
| `MARGIN` | 距屏幕边缘的距离（像素） | `12` | 任意非负整数 |

> 窗口高度不用配，脚本会按任务行数和字号自动算（封顶 8 行）。

### 改例子

**加摸鱼网站**（把抖音、知乎也算摸鱼）：往 `BLOCKLIST_TITLE` 加该网站标题里会出现的关键词。
```lua
local BLOCKLIST_TITLE = { "/ x", "twitter", "小红书", "youtube", "bilibili", "哔哩", "抖音", "知乎" }
```
> 怎么选关键词？打开那个网站，看浏览器标签/窗口标题写的字，挑一个稳定出现、又不会误伤正经页面的词。不区分大小写。

**加 App 黑名单**（开着 Telegram / Discord 也算摸鱼）：
```lua
local BLOCKLIST_APP = { "Telegram", "Discord" }
```

**调试时想快点看到催促通知**：把阈值临时调小，验证完改回。
```lua
local ALERT_THRESHOLD = 6   -- 6 秒就弹通知
local ALERT_INTERVAL  = 6
```
> 红卡片是一碰摸鱼就弹的（即时），这里调的只是「系统通知」的阈值。

---

## 七、重载 / 关掉 / 暂停 / 开机自启

- **重载**：⌘⌥⌃R，或菜单栏锤子 → Reload Config。
- **临时暂停**：⌘⌥⌃P，卡片隐藏、不盯不弹；再按恢复。
- **彻底关掉**：菜单栏锤子 → Quit Hammerspoon。
- **开机自启**：菜单栏锤子 → Preferences → 勾 **Launch Hammerspoon at login**。

---

## 八、常见问题

- **平时看不到卡片？** 设计如此——专注时隐身，只在你碰摸鱼网站时弹出来。想看到它，切到 X / 小红书等网站，红卡片立刻冒出来；切回干活又自动消失。
- **碰了摸鱼网站红卡片也不出现？** 依次排查：是否按过 ⌘⌥⌃P 暂停（再按恢复）→ **辅助功能权限**给了没（见第四节）→ Hammerspoon 在跑且已 Reload → Console 有没有报错 → 那个网站标题里有没有 `BLOCKLIST_TITLE` 的关键词，没有就加。
- **卡片位置怪 / 跑屏幕外？** 多屏或缩放比例特殊时坐标可能偏。改 `POSITION` 换个角，或调 `MARGIN`。
- **红卡片太大 / 挡东西？** 调小 `WIN_WIDTH`、调小字号、调低 `OPACITY`，或换 `POSITION`。它纯展示、不接收鼠标点击，不会抢焦点。

---

## License

[MIT](LICENSE)
