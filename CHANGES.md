# 改动说明：本地 MPRIS + 在线歌词

本文记录本仓库从「第三方音乐服务开发者账号 + Web API」改造为
「本地 MPRIS + 在线歌词」的实现细节。

## 仓库名

- GitHub 仓库：`mpris-lyrics-on-gnome`
- 来源：从 [`Haku060/sptlrx-lyrics-on-gnome`](https://github.com/Haku060/sptlrx-lyrics-on-gnome)
  fork 后改造。
- 原来的编译产物 `sptlrx` 已删除；管道脚本名、配置目录和 GNOME 扩展 UUID
  仍保留 `sptlrx` 前缀，以兼容已有安装。

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
sptlrx-pipe（Python）
  │  本地 .lrc → 在线歌词 eapi → 备用在线源
  ▼
/tmp/sptlrx-lyrics
  ▼
GNOME Shell 顶栏扩展
  sptlrx-lyrics@gnome-shell-extension
```

原来的 `sptlrx` 编译二进制已从仓库删除；状态栏管道和 GNOME 扩展都不再调用它。

## 文件清单

### 修改

| 文件 | 说明 |
|------|------|
| `sptlrx-pipe` | 完全重写为独立的 MPRIS + 歌词同步脚本 |
| `install.sh` | 安装管道、数据文件、GNOME 扩展和 systemd 服务 |
| `README.md` | 更新安装、歌词来源和使用说明 |

### 新增

| 文件 | 说明 |
|------|------|
| `gnome-extension/metadata.json` | GNOME Shell 扩展元数据 |
| `gnome-extension/extension.js` | 顶栏歌词扩展 |
| `gnome-extension/stylesheet.css` | 顶栏标签样式 |
| `data/TSCharacters.txt` | OpenCC 繁转简表，用于在线歌词匹配 |
| `THIRD_PARTY_NOTICES.md` | 第三方资源与许可证说明 |
| `CHANGES.md` | 本文件 |

### 删除

| 文件 | 说明 |
|------|------|
| `sptlrx` | 旧的 Go 编译二进制；状态栏管道不再使用，安装时会从 `~/.local/bin` 清理 |

## `sptlrx-pipe` 实现

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

空列表表示自动识别所有 `org.mpris.MediaPlayer2.*`。

选择规则：

1. 如果有音乐播放器刚刚从暂停变为播放，立即切换过去。
2. 当前播放器正在播放时，保持当前播放器。
3. 当前播放器暂停/停止，而另一个播放器正在播放时，切换过去。
4. 浏览器开始播放不会抢走正在播放的音乐。
5. 所有播放器都暂停时，保留当前播放器；没有当前播放器时，按会话总线
   枚举顺序选择。只有在「同时有多个候选」时，音乐播放器优先于浏览器，
   以落实第 4 条；不维护任何按 App 名称的固定优先级。

浏览器列表包括 Chromium、Chrome、Firefox、Brave、Edge、Opera、Vivaldi 等。

仍然可以手动固定播放器：

```sh
MPRIS_PLAYER=<player> ./install.sh
```

固定后会写入：

```yaml
mpris:
  players: [<player>]
```

### 3. 歌词来源

默认顺序：

```text
local,<online>,<fallback>
```

可以通过环境变量覆盖：

```sh
SPTLRX_LYRICS_SOURCES=<online>
SPTLRX_LYRICS_SOURCES=<online>,<fallback>
SPTLRX_LYRICS_SOURCES=local,<online>,<fallback>
```

#### 3.1 本地 `.lrc`

读取 `~/.config/sptlrx/config.yaml`：

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
- 歌词行每 0.15 秒根据播放进度计算一次。
- 两次 MPRIS 轮询之间使用本地时间插值，保证歌词切换平滑。
- 暂停：显示 `⏸ Paused`。
- 停止：显示 `⏹ Stopped`。
- 无播放器：显示 `⏹ No player`。
- 切歌：清空旧歌词，获取新歌词后显示当前行。
- 没有歌词时显示 `♫` 或空内容。

### 5. 进程与文件

| 路径 | 说明 |
|------|------|
| `/tmp/sptlrx-lyrics` | 当前歌词/状态输出文件 |
| `/tmp/sptlrx-lyrics.log` | 运行日志 |
| `/tmp/sptlrx-lyrics.pid` | 进程 PID 文件 |

脚本会检测 PID 文件，避免重复启动多个实例。

## GNOME Shell 扩展

扩展 UUID：

```text
sptlrx-lyrics@gnome-shell-extension
```

安装路径：

```text
~/.local/share/gnome-shell/extensions/sptlrx-lyrics@gnome-shell-extension/
```

行为：

- 每秒读取一次歌词文件。
- 在顶栏右侧显示当前行。
- 内容为空时自动隐藏。
- 最长显示 75 个字符，超出部分截断。

第一次安装后需要重启 GNOME Shell：

- X11：`Alt+F2` → 输入 `r` → 回车
- Wayland：注销并重新登录

## 安装与 systemd

`install.sh` 会：

1. 删除旧版本遗留的 `~/.local/bin/sptlrx` 编译二进制。
2. 原子替换 `sptlrx-pipe`，避免运行中替换出现 `Text file busy`。
3. 安装 `data/TSCharacters.txt` 到 `$PREFIX/share/sptlrx/`。
4. 安装并启用 GNOME 扩展。
5. 写入 `~/.config/sptlrx/config.yaml`：
   - `player: mpris`
   - `mpris.players: []`（除非指定 `MPRIS_PLAYER`）
6. 写入并启动 systemd 用户服务：

```text
~/.config/systemd/user/sptlrx-pipe.service
```

服务默认内容：

```ini
[Unit]
Description=MPRIS lyrics pipe (local MPRIS)
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=%h/.local/bin/sptlrx-pipe /tmp/sptlrx-lyrics
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
`~/.config/autostart/sptlrx-pipe.desktop` + `nohup`。

## 常用命令

```sh
# 查看服务
systemctl --user status sptlrx-pipe.service

# 重启管道
systemctl --user restart sptlrx-pipe.service

# 查看当前输出
cat /tmp/sptlrx-lyrics

# 查看日志
tail -f /tmp/sptlrx-lyrics.log

# 查看扩展状态
gnome-extensions info sptlrx-lyrics@gnome-shell-extension

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

## 已知限制

- 在线歌词源使用免登录公开接口，接口行为可能随平台调整而变化。
- 部分歌曲受地区/版权限制，可能搜索到现场版、翻唱版或无歌词；
  匹配会结合歌名、歌手和时长尽量选择正确版本。
- 暂未合并在线歌词源的翻译歌词。
- 浏览器如果单独播放媒体，也会被识别为有效 MPRIS 来源；这是「识别所有
  MPRIS」的预期行为。
- GNOME 扩展面向 GNOME Shell 45 / 46 / 47。

## 第三方资源

- 在线歌词 eapi 请求格式参考 Lyricify 开源实现
  （Apache-2.0，详见 `THIRD_PARTY_NOTICES.md`）。
- 繁简转换数据来自
  [OpenCC](https://github.com/BYVoid/OpenCC)（Apache-2.0）。
