-- ============================================================
-- focus-nanny  专注监工小狗 🐶
-- Hammerspoon 配置脚本 / MVP 最终版
-- 功能：右上角常驻悬浮窗，提醒今日任务 + 监控摸鱼，超时弹提醒。
-- 纯 Lua，只用 Hammerspoon 内置 API，无外部依赖。
--
-- 摸鱼判定原理：读「前台窗口标题」(hs.window.focusedWindow():title())，
-- 与 BLOCKLIST_TITLE 关键词做小写子串匹配，命中即算摸鱼。
-- 为什么不抓浏览器 URL？本机 Chrome 的 AppleScript 接口恒报
-- `count of windows = 0`，URL 永远读不到（Chrome 已知毛病）；
-- 而窗口标题走「辅助功能」权限，稳定可读，所以最终改用标题方案。
-- ============================================================

-- ====================== 配置区（在这里改设置） ======================
-- 今日任务文件：每行一条任务，第一行最重要。
-- 想换文件位置，改这行的路径即可。
local TASK_FILE = os.getenv("HOME") .. "/Desktop/今日任务.txt"

-- 摸鱼网站名单：前台窗口标题（转小写后）含其中任意关键词，就算摸鱼。
-- 想扩展摸鱼名单 → 往这里加「网站标题里会出现的关键词」即可。
-- 提示：推特标题形如 "(1) 主页 / X"，所以用 "/ x" 命中；
--       小红书/YouTube/B 站等标题里通常带站点名，直接加站点名关键词。
local BLOCKLIST_TITLE = { "/ x", "twitter", "小红书", "youtube", "bilibili", "哔哩" }

-- App 名黑名单：前台 app 名命中即算摸鱼（默认空，预留扩展）。
-- 例如填 { "Telegram", "Discord" } 就会把这俩 app 也算摸鱼。
local BLOCKLIST_APP = {}

-- 阈值（想更灵敏就调小，调试时可把 ALERT_THRESHOLD 临时改成 6 秒）
local ALERT_THRESHOLD = 300   -- 连续摸鱼多少秒后【开始】提醒（秒）= 5 分钟
local ALERT_INTERVAL  = 300   -- 提醒后每隔多少秒再提醒一次，避免狂弹（秒）
local CHECK_INTERVAL  = 2     -- 每几秒检查一次（秒）
-- ====================== 配置区结束 ======================


-- ====================== 运行时状态 ======================
local slackSeconds = 0        -- 已连续摸鱼累计秒数
local lastAlertAt  = 0        -- 上次提醒的时间戳（hs.timer.secondsSinceEpoch）
local nanny = {}              -- 命名空间，存 canvas / timer 等，防止被 GC 回收
nanny.paused = false          -- 监工开关：true=暂停盯梢（⌘⌥⌃P 切换）
-- ======================================================


-- ====================== 工具函数 ======================

-- 安全读今日任务文件。返回 (完整文本, 第一行)。
-- 文件不存在 / 读失败 / 空 → 返回占位提示文案。
local function readTasks()
    local placeholder = "还没设置今日任务，去编辑 ~/Desktop/今日任务.txt"
    -- 用 pcall 包住整段 io 操作，任何异常都不让它崩
    local ok, content = pcall(function()
        local f = io.open(TASK_FILE, "r")
        if not f then return nil end
        local data = f:read("*a")
        f:close()
        return data
    end)

    if not ok or not content then
        return placeholder, placeholder
    end

    -- 去掉首尾空白，判空
    local trimmed = content:gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed == "" then
        return placeholder, placeholder
    end

    -- 取第一行（用于通知里点名）
    local firstLine = trimmed:match("^[^\r\n]*") or trimmed
    return trimmed, firstLine
end

-- 判断当前是否摸鱼。返回 (是否摸鱼:boolean)
-- 依据两路：1) 前台 app 名命中 BLOCKLIST_APP；2) 窗口标题命中 BLOCKLIST_TITLE。
local function isSlacking(appName, winTitle)
    -- 1) app 名命中黑名单
    for _, blockedApp in ipairs(BLOCKLIST_APP) do
        if appName == blockedApp then
            return true
        end
    end

    -- 2) 窗口标题（小写）子串命中黑名单关键词
    if winTitle and winTitle ~= "" then
        local lt = winTitle:lower()
        for _, keyword in ipairs(BLOCKLIST_TITLE) do
            -- 第三个参数 true = 纯文本查找，不当成 Lua 模式，避免特殊字符踩坑
            if lt:find(keyword:lower(), 1, true) then
                return true
            end
        end
    end

    return false
end

-- 把秒数格式化成 "X 分Y秒"
local function fmtDuration(sec)
    local m = math.floor(sec / 60)
    local s = sec % 60
    return string.format("%d 分%d秒", m, s)
end

-- ======================================================


-- ====================== 悬浮窗（hs.canvas） ======================
-- ===== 悬浮窗外观（想调大小/透明度/位置，改这几行就行）=====
local WIN_WIDTH   = 260       -- 窗口宽度(像素)：想更小调小、更大调大
local FONT_TITLE  = 15        -- 「今日任务」标题字号
local FONT_TASK   = 13        -- 任务文字字号
local FONT_STATUS = 13        -- 底部状态行字号
local OPACITY     = 0.78      -- 透明度：0=全透明 ~ 1=完全不透明，越小越透
local POSITION    = "topright"-- 位置：topright / topleft / bottomright / bottomleft
local MARGIN      = 12        -- 距屏幕边缘的距离(像素)
-- ==========================================================

-- 安全获取主屏可用区域的右上角坐标。取不到坐标也不崩。
local function computeFrame(height)
    local ok, frame = pcall(function()
        local screen = hs.screen.mainScreen()
        if not screen then return nil end
        return screen:frame()   -- 屏幕可用区（菜单栏下方）
    end)

    if ok and frame then
        local x, y
        if POSITION == "topleft" then
            x, y = frame.x + MARGIN, frame.y + MARGIN
        elseif POSITION == "bottomright" then
            x, y = frame.x + frame.w - WIN_WIDTH - MARGIN, frame.y + frame.h - height - MARGIN
        elseif POSITION == "bottomleft" then
            x, y = frame.x + MARGIN, frame.y + frame.h - height - MARGIN
        else -- 默认右上角 topright
            x, y = frame.x + frame.w - WIN_WIDTH - MARGIN, frame.y + MARGIN
        end
        return { x = x, y = y, w = WIN_WIDTH, h = height }
    end
    -- 兜底：拿不到屏幕信息就放左上角，至少不崩
    return { x = 100, y = 100, w = WIN_WIDTH, h = height }
end

-- 创建（或返回已有的）canvas
local function ensureCanvas()
    if nanny.canvas then return nanny.canvas end
    local c = hs.canvas.new(computeFrame(120))
    if not c then return nil end   -- 极端情况下创建失败，直接返回 nil，调用方自会跳过
    -- 置顶层级：overlay 在普通窗口之上
    c:level(hs.canvas.windowLevels.overlay)
    -- 跨所有桌面/Space 常驻
    c:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
    -- 本工具的 canvas 没绑鼠标回调，默认就不接收点击、不抢焦点；
    -- 这行进一步确保即便日后加了点击回调，点它也不会激活 Hammerspoon 抢走前台焦点。
    c:clickActivating(false)
    nanny.canvas = c
    return c
end

-- 根据状态刷新悬浮窗内容
-- slacking:boolean, statusText:string, taskText:string
local function renderCanvas(slacking, statusText, taskText)
    local c = ensureCanvas()
    if not c then return end   -- 拿不到 canvas 就跳过本次渲染，不崩

    -- 配色：专注态深色，摸鱼态偏红；透明度由 OPACITY 控制
    local bgColor
    if slacking then
        bgColor = { red = 0.55, green = 0.10, blue = 0.10, alpha = math.min(OPACITY + 0.12, 1.0) }
    else
        bgColor = { red = 0.10, green = 0.11, blue = 0.13, alpha = OPACITY }
    end

    local title = "🎯 今日任务"

    -- 动态估算高度（随任务行数变，封顶 8 行），字号由配置决定
    local taskLines = 1
    for _ in taskText:gmatch("\n") do taskLines = taskLines + 1 end
    if taskLines > 8 then taskLines = 8 end
    local pad        = 10                 -- 左右内边距
    local padTop     = 8
    local lineH      = FONT_TASK + 5
    local titleH     = FONT_TITLE + 7
    local taskBlockH = taskLines * lineH + 4
    local statusH    = FONT_STATUS + 7
    local totalH     = padTop + titleH + taskBlockH + statusH + padTop

    c:frame(computeFrame(totalH))

    c:replaceElements(
        {
            type = "rectangle", action = "fill", fillColor = bgColor,
            roundedRectRadii = { xRadius = 10, yRadius = 10 },
            frame = { x = 0, y = 0, w = "100%", h = "100%" },
        },
        {
            type = "text", text = title,
            textColor = { white = 1.0, alpha = 1.0 },
            textSize = FONT_TITLE, textFont = ".AppleSystemUIFontBold",
            frame = { x = pad, y = padTop, w = WIN_WIDTH - pad * 2, h = titleH },
        },
        {
            type = "text", text = taskText,
            textColor = { white = 0.92, alpha = 1.0 },
            textSize = FONT_TASK,
            frame = { x = pad, y = padTop + titleH, w = WIN_WIDTH - pad * 2, h = taskBlockH },
        },
        {
            type = "text", text = statusText,
            textColor = slacking
                and { red = 1.0, green = 0.9, blue = 0.5, alpha = 1.0 }
                or  { red = 0.5, green = 0.95, blue = 0.6, alpha = 1.0 },
            textSize = FONT_STATUS, textFont = ".AppleSystemUIFontBold",
            frame = { x = pad, y = padTop + titleH + taskBlockH, w = WIN_WIDTH - pad * 2, h = statusH },
        }
    )

    c:show()
end
-- ======================================================


-- ====================== 监控主循环 ======================
local function tick()
    -- 全程包 pcall，单次 tick 出错不影响 timer 继续跑
    local ok, err = pcall(function()
        -- 0) 暂停态：藏起来、不计时、直接跳过本轮
        if nanny.paused then
            if nanny.canvas then pcall(function() nanny.canvas:hide() end) end
            return
        end

        -- 1) 前台 app 名
        local appName = ""
        local app = hs.application.frontmostApplication()
        if app then appName = app:name() or "" end

        -- 2) 前台窗口标题（走辅助功能权限，比 Chrome AppleScript 稳，是摸鱼判定主依据）
        --    取窗口和读标题都包进 pcall：窗口取到后瞬间被销毁时 w:title() 也不会抛错。
        local winTitle = ""
        local okT, t = pcall(function()
            local w = hs.window.focusedWindow()
            if w then return w:title() end
            return ""
        end)
        if okT and type(t) == "string" then winTitle = t end

        -- 3) 摸鱼判定（app 名 + 窗口标题关键词）
        local slacking = isSlacking(appName, winTitle)

        -- 4) 计时
        if slacking then
            slackSeconds = slackSeconds + CHECK_INTERVAL
        else
            slackSeconds = 0
            lastAlertAt = 0   -- 离开摸鱼态就重置提醒节流
        end

        -- 5) 读任务（实时）
        local taskText, firstLine = readTasks()

        -- 6) 状态行文案
        local statusText
        if slacking then
            statusText = "⚠️ 摸鱼中 " .. fmtDuration(slackSeconds) .. " · 今天要干活！"
        else
            local showName = (appName ~= "" and appName) or "未知"
            statusText = "✅ 专注中 · " .. showName
        end

        -- 7) 专注时隐藏不挡活；一碰摸鱼立刻现身、变红计时
        if slacking then
            renderCanvas(true, statusText, taskText)
        elseif nanny.canvas then
            pcall(function() nanny.canvas:hide() end)
        end

        -- 8) 提醒（跨过阈值 + 距上次提醒够久才弹）
        if slacking and slackSeconds >= ALERT_THRESHOLD then
            local now = hs.timer.secondsSinceEpoch()
            if (now - lastAlertAt) >= ALERT_INTERVAL then
                lastAlertAt = now
                local mins = math.floor(slackSeconds / 60)
                hs.notify.new({
                    title = "🚨 喂！",
                    informativeText = "你已经摸鱼 " .. mins .. " 分钟了，今天要：" .. firstLine,
                }):send()
            end
        end
    end)

    if not ok then
        -- 出错只打日志，不崩、不打断 timer
        print("[focus-nanny] tick 出错: " .. tostring(err))
    end
end
-- ======================================================


-- ====================== 启动 ======================
-- 先建好窗口但默认隐藏：专注时不挡活，一碰摸鱼才现身
ensureCanvas()
if nanny.canvas then pcall(function() nanny.canvas:hide() end) end

-- 启动监控 timer
nanny.timer = hs.timer.doEvery(CHECK_INTERVAL, tick)

-- 开关监工：cmd+alt+ctrl+P 暂停/恢复（暂停后彻底不盯、不弹、不显示）
hs.hotkey.bind({ "cmd", "alt", "ctrl" }, "P", function()
    nanny.paused = not nanny.paused
    if nanny.paused then
        slackSeconds = 0
        if nanny.canvas then pcall(function() nanny.canvas:hide() end) end
        hs.alert.show("😴 监工已暂停（再按 ⌘⌥⌃P 恢复）")
    else
        hs.alert.show("🐶 监工已恢复，继续盯你")
    end
end)

-- 调试用：cmd+alt+ctrl+R 重载配置
hs.hotkey.bind({ "cmd", "alt", "ctrl" }, "R", function()
    hs.reload()
end)

-- 启动提示
hs.alert.show("focus-nanny 上岗 🐶 专注时隐身·一碰摸鱼就现 · ⌘⌥⌃P 暂停")
-- ======================================================
