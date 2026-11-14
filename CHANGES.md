# 改动说明：本地 MPRIS + 在线歌词

本文记录本仓库从「第三方音乐服务开发者账号 + Web API」改造为
「本地 MPRIS + 在线歌词」的实现细节。

## 仓库名

- GitHub 仓库：`mpris-lyrics-on-gnome`
- 来源：从 [`Haku060/sptlrx-lyrics-on-gnome`](https://github.com/Haku060/sptlrx-lyrics-on-gnome)
  fork 后改造。
- 原来的编译产物 `sptlrx` 已删除。
- 当前版本已把脚本、服务、配置目录、数据目录、输出文件和 GNOME 扩展 UUID
  统一为 `mpris-lyrics` 前缀；安装脚本会自动迁移旧安装。

## 目标

1. 不再依赖第三方音乐服务开发者账号、Client ID/Secret 或登录步骤。
2. 播放信息全部来自本地 MPRIS（D-Bus）。
3. 自动识别所有有效的 MPRIS 播放器，而不是固定某一个播放器。
4. 歌词来源不再局限于单一在线源：优先使用在线歌词源，备用源兜底。
5. 在 GNOME 顶栏显示当前歌词，并在暂停、停止、切歌时正确更新。

## 整体结构

改造后的数据流：

```text
MPRIS 播放器
  │  PlaybackStatus / Metadata / Position / mpris:length
  ▼
mpris-lyrics-pipe（Python）
  │  本地 .lrc / 在线歌词源 → 评分
  ▼
/tmp/mpris-lyrics
  ▼
GNOME Shell 顶栏扩展
  mpris-lyrics@gnome-shell-extension
```

原来的 `sptlrx` 编译二进制已从仓库删除；状态栏管道和 GNOME 扩展都不再调用它。

## 文件清单

### 修改

| 文件 | 说明 |
|------|------|
| `mpris-lyrics-pipe` | 完全重写为独立的 MPRIS + 歌词同步脚本 |
| `install.sh` | 安装管道、数据文件、GNOME 扩展、设置 schema 和 systemd 服务 |
| `README.md` | 更新安装、歌词来源、评分、设置和显示行为 |

### 新增

| 文件 | 说明 |
|------|------|
| `gnome-extension/metadata.json` | GNOME Shell 扩展元数据 |
| `gnome-extension/extension.js` | 顶栏歌词扩展、点击菜单和设置联动 |
| `gnome-extension/prefs.js` | GNOME 扩展设置页 |
| `gnome-extension/org.gnome.shell.extensions.mpris-lyrics.gschema.xml` | 扩展设置 schema |
| `gnome-extension/stylesheet.css` | 顶栏标签样式 |
| `data/TSCharacters.txt` | OpenCC 繁转简表，用于在线歌词匹配 |
| `THIRD_PARTY_NOTICES.md` | 第三方资源与许可证说明 |
| `CHANGES.md` | 本文件 |

### 删除

| 文件 | 说明 |
|------|------|
| `sptlrx` | 旧的 Go 编译二进制；状态栏管道不再使用，安装时会从 `~/.local/bin` 清理 |

## `mpris-lyrics-pipe` 实现

### 1. MPRIS 读取

通过 `gdbus` 调用会话总线：

```text
org.freedesktop.DBus.ListNames
org.mpris.MediaPlayer2.Player
  - PlaybackStatus
  - Metadata
  - Position
  - mpris:length
```

支持：

- `xesam:title`
- `xesam:artist`（字符串或字符串数组）
- `mpris:trackid`
- `mpris:length`（`int64` 和 `uint64` 都支持）
- `Position`（微秒转换为毫秒）

### 2. 自动选择播放器

默认配置：

```yaml
mpris:
  players: []
```

空列表表示自动识别所有音乐类 `org.mpris.MediaPlayer2.*`；浏览器 MPRIS 会被排除。

选择规则：

1. 如果有音乐播放器刚刚从暂停变为播放，立即切换过去。
2. 当前音乐播放器正在播放时，保持当前播放器。
3. 当前音乐播放器暂停/停止，而另一个音乐播放器正在播放时，切换过去。
4. 浏览器（Chromium、Chrome、Firefox、Brave、Edge、Opera、Vivaldi 等）
   永远不参与歌词显示，也不会抢走当前音乐播放器。
5. 所有音乐播放器都暂停时，保留当前播放器；没有当前播放器时，按会话总线
   枚举顺序选择音乐播放器。不维护任何按 App 名称的固定优先级。

仍然可以手动固定播放器：

```sh
MPRIS_PLAYER=<player> ./install.sh
```

固定后会写入：

```yaml
mpris:
  players: [<player>]
```

### 3. 歌词来源与评分

所有启用的源都会参与评分，选择综合得分最高的候选：

```text
total = match + quality + bonus
```

- `match`：歌名、歌手、时长、版本标记
- `quality`：歌词行数、非空行比例、时间轴覆盖范围
- `bonus`：本地 `.lrc` 略高

没有合格候选时返回空，播放中由管道显示 `♫`，不强行使用低置信度结果。

`MPRIS_LYRICS_SOURCES` 用于选择参与评分的源，不是优先级顺序：

```sh
MPRIS_LYRICS_SOURCES=<online>
MPRIS_LYRICS_SOURCES=<online>,<fallback>
MPRIS_LYRICS_SOURCES=local,<online>,<fallback>
```

版本标记会精确比较，例如 `说唱版` 不会匹配 `2024`；`Live Forever`
不会被误判为 Live 版。LRCLIB 的 `/api/get` 失败时会继续尝试
`/api/search`，search 失败会重试一次。

#### 3.1 本地 `.lrc`

读取 `~/.config/mpris-lyrics/config.yaml`：

```yaml
local:
  folder: ~/Music/lyrics
```

启动时扫描目录内所有 `.lrc` 文件，按文件名中的歌手/歌名匹配。

#### 3.2 在线歌词源

参考开源歌词工具的公开 eapi 请求方式：

- 搜索：
  `https://<online-lyrics-host>/eapi/cloudsearch/pc`
- 歌词：
  `https://<online-lyrics-host>/eapi/song/lyric/v1`

eapi 加密流程：

1. 构造 `params` 明文。
2. 计算 MD5 摘要。
3. 使用 AES-128-ECB（密钥 `e82ckenh8dichen8`）加密。
4. 十六进制大写后作为表单提交。

AES 实现优先使用 Python 的 `cryptography`，没有时回退到系统 `openssl`。

匹配策略：

- 歌名：精确匹配、包含匹配。
- 歌手：精确匹配、包含匹配。
- 时长：结合 MPRIS 的 `mpris:length` 与在线歌词源的 `duration`/`dt`。
- 繁简转换：`data/TSCharacters.txt` 将繁体歌名/歌手转为简体后再比较，
  例如 `張敬軒 酷愛` → `张敬轩 酷爱`。

歌词解析：

- 优先 `lrc.lyric`。
- LRC 行数不足时尝试 `yrc.lyric`。
- 支持一行多个时间戳、`[offset:...]`、空行和元数据行。

#### 3.3 LRCLIB

- `https://lrclib.net/api/get?artist_name=...&track_name=...`
- 失败时使用 `https://lrclib.net/api/search?q=...`
- 只使用 `syncedLyrics`。

### 4. 同步与状态

- MPRIS 状态每 1 秒轮询一次。
- 歌词行每 0.1 秒根据播放进度计算一次。
- 顶栏扩展每 0.1 秒读取一次歌词文件，避免状态栏刷新造成 1 秒延迟。
- 两次 MPRIS 轮询之间使用本地时间插值，保证歌词切换平滑。
- 支持 `MPRIS_LYRICS_OFFSET_MS` 全局偏移；正数让歌词提前，负数让歌词延后。
- 根据系统语言自动处理简繁：`zh_CN` / `zh_SG` 时歌词和歌名都显示简体；
  可用 `MPRIS_LYRICS_CHINESE_SCRIPT=simplified|original` 覆盖。
- 暂停：显示 `⏸ Paused`。
- 停止：显示 `⏹ Stopped`。
- 无播放器：显示 `⏹ No player`。
- 切歌：清空旧歌词，获取新歌词后显示当前行。
- 没有匹配到歌词时显示歌曲名字；歌名不可用时显示 `♫`。

### 5. 进程与文件

| 路径 | 说明 |
|------|------|
| `/tmp/mpris-lyrics` | 当前歌词/状态输出文件 |
| `/tmp/mpris-lyrics.log` | 运行日志 |
| `/tmp/mpris-lyrics.pid` | 进程 PID 文件 |

脚本会检测 PID 文件，避免重复启动多个实例。

## GNOME Shell 扩展

扩展 UUID：

```text
mpris-lyrics@gnome-shell-extension
```

安装路径：

```text
~/.local/share/gnome-shell/extensions/mpris-lyrics@gnome-shell-extension/
```

设置 schema：

```text
org.gnome.shell.extensions.mpris-lyrics
```

schema 安装到 `$PREFIX/share/glib-2.0/schemas/`，并通过
`glib-compile-schemas` 编译。设置页由 `prefs.js` 提供。

行为：

- 按 `refresh-interval-ms`（默认 100 ms）读取歌词文件。
- 顶栏位置和顺序可配置；修改时移除旧指示器，并用新的唯一 role
  重新添加，避免旧 role 导致位置不生效。
- 点击歌词打开菜单，菜单里有 **Settings** 入口。
- 菜单以歌词项为中心弹出，Shell 会自动限制在屏幕范围内。
- 间奏/空歌词行保留上一句。
- 已匹配到歌词、但还没到第一句时显示歌曲名字。
- 未匹配到歌词时显示歌曲名字；没有歌名时显示 `♫`。
- 可选永久在歌名/歌词前显示 `♫`。
- 空内容是否隐藏、是否显示暂停/停止状态可配置。
- 最大长度、字号、文字颜色可配置。

设置项：

| 设置 | 说明 |
|------|------|
| `Maximum text length` | 顶栏最多显示多少个字符 |
| `Hide when empty` | 内容为空时是否隐藏 |
| `Show playback status` | 是否显示 `⏸` / `⏹` 状态 |
| `Always show music icon` | 是否在歌名/歌词前永久显示 `♫` |
| `Panel position` | 左 / 中 / 右区域 |
| `Panel order` | 同区域内的顺序 |
| `Font size` | 字号，`0` 使用面板默认 |
| `Text color` | 文字颜色，例如 `#ffcc00` |
| `Refresh interval` | 读取歌词文件的间隔（毫秒） |

第一次安装后需要重启 GNOME Shell：

- X11：`Alt+F2` → 输入 `r` → 回车
- Wayland：注销并重新登录

实现修复记录：

- GSettings 布尔值必须使用 `get_boolean()`，不能使用不存在的
  `get_bool()`；后者会导致扩展加载报错。
- 顶栏位置切换不能复用旧的 panel role，否则 Shell 会保留旧位置；
  现在每次重建使用唯一 role。
- 歌词文件中的空行会在返回前过滤，保证间奏时保留上一句。
- 管道在切歌时记录歌曲名；如果歌词已匹配但还没到第一句，输出歌曲名；
  如果没有匹配到歌词，也输出歌曲名（没有歌名时用 `♫`）。
- 歌名会先做 NFKC 归一化，再按系统语言转简体/保留原文。
- 在线歌词搜索先做 NFKC 归一化，避免兼容汉字/康熙部首导致搜不到。
- LRCLIB 的 `/api/get` 失败后仍会继续 `/api/search`，search 失败重试一次。
- 扩展新增 `prefix-icon` 设置，开启后在歌名和歌词前显示 `♫`。

## 安装与 systemd

`install.sh` 会：

1. 迁移旧安装：停止旧服务、复制旧配置、迁移旧 dconf 设置，并删除旧扩展、
   schema、服务、脚本和输出文件。
2. 删除旧版本遗留的 `~/.local/bin/sptlrx` 编译二进制。
3. 原子替换 `mpris-lyrics-pipe`，避免运行中替换出现 `Text file busy`。
4. 安装 `data/TSCharacters.txt` 到 `$PREFIX/share/mpris-lyrics/`。
5. 安装 GNOME 扩展、`prefs.js` 和 GSettings schema，并运行
   `glib-compile-schemas`。
6. 写入 `~/.config/mpris-lyrics/config.yaml`：
   - `player: mpris`
   - `mpris.players: []`（除非指定 `MPRIS_PLAYER`）
7. 写入并启动 systemd 用户服务：

```text
~/.config/systemd/user/mpris-lyrics.service
```

服务默认内容：

```ini
[Unit]
Description=MPRIS lyrics pipe (local MPRIS)
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=%h/.local/bin/mpris-lyrics-pipe /tmp/mpris-lyrics
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
```

使用 systemd 的原因：

- 以 `unconfined` 身份运行，可以读取某些受 AppArmor 限制的 snap 播放器。
- 自动重启。
- 不依赖桌面会话里某个终端进程。

如果系统不支持 systemd 用户服务，则回退到
`~/.config/autostart/mpris-lyrics.desktop` + `nohup`。

## 常用命令

```sh
# 查看服务
systemctl --user status mpris-lyrics.service

# 重启管道
systemctl --user restart mpris-lyrics.service

# 查看当前输出
cat /tmp/mpris-lyrics

# 查看日志
tail -f /tmp/mpris-lyrics.log

# 查看扩展状态
gnome-extensions info mpris-lyrics@gnome-shell-extension

# 查看 MPRIS 播放器
busctl --user list | grep -i mpris
```

## 已验证场景

- 模拟 MPRIS 播放器：播放、暂停、恢复、切歌。
- 多个 MPRIS 播放器：自动选择正在播放的那个。
- 本地播放器正在播放时自动切换并获取歌词。
- 当前播放器暂停、另一个播放器播放时能正确切换。
- 浏览器暂停时不会抢占正在播放的音乐。
- 在线歌词、备用在线源、本地 `.lrc` 三条路径。
- 顶栏扩展实际显示歌词。
- 扩展设置页可以打开，修改设置会生效。
- 顶栏位置/顺序修改后，歌词项会移动到对应区域。
- 点击歌词会弹出菜单，Settings 入口可以打开设置页。
- 间奏时保留上一句歌词；开头/无歌词时显示 `♫`。

## 已知限制

- 在线歌词源使用免登录公开接口，接口行为可能随平台调整而变化。
- 部分歌曲受地区/版权限制，可能搜索到现场版、翻唱版或无歌词；
  匹配会结合歌名、歌手和时长尽量选择正确版本。
- 暂未合并在线歌词源的翻译歌词。
- 浏览器如果单独播放媒体，也会被识别为有效 MPRIS 来源；这是「识别所有
  MPRIS」的预期行为。
- 设置页依赖 `glib-compile-schemas` 和 GSettings；缺少时安装脚本会给出警告。
- 菜单靠近屏幕边缘时会被 Shell 自动偏移以保持可见，因此不能保证严格
  相对屏幕居中。
- GNOME 扩展面向 GNOME Shell 45 / 46 / 47。

## 第三方资源

- 在线歌词 eapi 请求格式参考 Lyricify 开源实现
  （Apache-2.0，详见 `THIRD_PARTY_NOTICES.md`）。
- 繁简转换数据来自
  [OpenCC](https://github.com/BYVoid/OpenCC)（Apache-2.0）。
