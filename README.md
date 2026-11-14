# MPRIS Lyrics on GNOME

在 GNOME 顶栏显示本地播放器的同步歌词。

> **AI 辅助说明：** 本项目在 AI 辅助下完成，包括代码改造、文档编写和调试。

> **仓库名：** `mpris-lyrics-on-gnome`
>
> 本项目从 [`Haku060/sptlrx-lyrics-on-gnome`](https://github.com/Haku060/sptlrx-lyrics-on-gnome)
> fork 后改造而来。原来的编译产物 `sptlrx` 已经删除；当前版本已把脚本、服务、
> 配置目录、输出文件和 GNOME 扩展 UUID 统一为 `mpris-lyrics` 前缀。安装脚本会
> 自动迁移旧安装。

播放信息全部来自本地 MPRIS（D-Bus），不依赖任何第三方音乐服务账号。
任何支持 MPRIS 的本地播放器都可以使用。

## 安装

```sh
chmod +x install.sh
./install.sh
```

安装脚本会自动迁移旧版本：停止旧服务、复制旧配置、迁移旧扩展设置，并删除
旧的脚本、服务、扩展和输出文件。状态栏管道和扩展都不再使用 `sptlrx` 二进制。

可选自定义：

```sh
PREFIX=/usr/local PIPE_PATH=/tmp/my-lyrics ./install.sh
```

默认会自动识别所有音乐类 MPRIS 播放器，并优先跟随当前正在播放的那个。
如果都暂停了，会保留最后一次使用的播放器。

浏览器（Chrome、Firefox、Edge 等）不参与歌词显示，也不会抢走当前音乐播放器。
不会给某个具体 App 设置固定优先级；多个音乐播放器之间按
「新开始播放的音乐播放器 > 当前播放器 > 其他正在播放的播放器」仲裁。

安装脚本会写入 `~/.config/mpris-lyrics/config.yaml`：

```yaml
player: mpris
mpris:
  players: []          # 空 = 自动识别所有音乐类 MPRIS 播放器
```

如果想强制只用一个播放器，先查看本机的 MPRIS 总线名：

```sh
busctl --user list | grep -i mpris
```

然后使用总线名的后缀固定：

```sh
MPRIS_PLAYER=<播放器后缀> ./install.sh
```

固定后会写入：

```yaml
mpris:
  players: [<播放器后缀>]
```

之后也可以手动编辑这个文件。改完重启：

```sh
systemctl --user restart mpris-lyrics.service
```

**第一次安装后需要重启 GNOME Shell 才会加载顶栏扩展：**

- X11：按 `Alt+F2`，输入 `r`，回车
- Wayland：注销并重新登录

之后顶栏会显示当前歌词行。默认在左侧，可以在扩展设置里改到左/中/右；
间奏会保留上一句；开头或没有匹配到歌词时显示歌曲名字，歌名不可用时显示 `♫`。

## 包含

| 文件 | 说明 |
|------|------|
| `mpris-lyrics-pipe` | Python 管道脚本 — 读取本地 MPRIS，获取并同步歌词 |
| `gnome-extension/` | GNOME Shell 顶栏扩展 — 显示歌词、点击菜单和设置页 |
| `gnome-extension/prefs.js` | 扩展设置页 |
| `gnome-extension/org.gnome.shell.extensions.mpris-lyrics.gschema.xml` | 扩展设置 schema |
| `data/TSCharacters.txt` | 繁简转换表，用于匹配在线歌词源 |
| `mpris-lyrics.desktop` | 无 systemd 时的登录自启 |

## 扩展设置

在“扩展管理器”里找到 **MPRIS Lyrics** → 设置，或者直接点击顶栏歌词 →
**Settings**，即可调整：

| 设置 | 说明 |
|------|------|
| Maximum text length | 顶栏最多显示多少个字符 |
| Hide when empty | 内容为空时是否隐藏 |
| Show playback status | 是否显示 `⏸` / `⏹` 状态 |
| Always show music icon | 是否在歌名和歌词前永久显示 `♫` |
| Panel position | 放到顶栏的左 / 中 / 右区域 |
| Panel order | 在同一区域内的排列顺序 |
| Font size | 字号，`0` 表示使用面板默认 |
| Text color | 文字颜色，例如 `#ffcc00` |
| Refresh interval | 读取歌词文件的间隔（毫秒） |

设置会立即生效。修改顶栏位置或顺序时，扩展会自动重建指示器。

## 显示行为

- **间奏或空歌词行**：保留上一句歌词，直到下一句非空歌词出现
- **已匹配到歌词、但还没到第一句**：显示歌曲名字
- **未匹配到歌词**：显示歌曲名字；歌名不可用时显示 `♫`
- **Always show music icon**：开启后，歌名和正常歌词前都会永久显示 `♫`
- **暂停 / 停止**：显示 `⏸ Paused` / `⏹ Stopped`，可通过设置关闭
- **点击歌词**：打开菜单，选择 **Settings** 进入设置页
- **菜单位置**：以歌词项为中心弹出，并由 GNOME Shell 自动限制在屏幕范围内

## 使用前提

1. 任意支持 MPRIS 的本地播放器
2. `gdbus`（GLib 自带；Debian/Ubuntu 包名 `libglib2.0-bin`）
3. GNOME Shell 45 / 46 / 47

## 歌词来源与评分

所有启用的歌词源都会参与评分，选择**综合得分最高**的候选，而不是按顺序
“谁先返回就用谁”。

默认参与评分的源：

1. **本地 `.lrc` 文件**（如果配置了 `local.folder`）
2. **在线歌词源**
3. **备用在线歌词源**

每个候选会计算：

- **匹配分**：歌名、歌手、时长、版本标记
- **质量分**：歌词行数、非空行比例、时间轴覆盖范围
- **源加权**：本地 `.lrc` 略高

```text
total = match + quality + bonus
```

如果最高分没有达到阈值，就显示空内容或 `♫`，不会强行使用翻唱、
Live、Remix 或版本不匹配的歌词。

`MPRIS_LYRICS_SOURCES` 用于选择**参与评分的源**，不是优先级顺序。
具体可用值见 `mpris-lyrics-pipe` 顶部的 `LYRICS_SOURCES`：

```sh
MPRIS_LYRICS_SOURCES=<source1>,<source2> systemctl --user restart mpris-lyrics.service
```

也可以写进 systemd 服务：

```ini
Environment=MPRIS_LYRICS_SOURCES=<source1>,<source2>
```

本地 `.lrc` 目录可以这样配置：

```yaml
# ~/.config/mpris-lyrics/config.yaml
local:
  folder: ~/Music/lyrics
```

文件名包含歌手和歌名即可，例如：

```text
~/Music/lyrics/歌手 - 歌名.lrc
```

匹配时会先做繁转简，并精确比较版本标记（如 `Live`、`Remix`、
`说唱版`、`2024`、`抒情版`），再结合歌名、歌手和 `mpris:length`
时长。版本不一致的候选会被排除。

## 同步微调

歌词按本地 MPRIS 的播放位置同步。管道每 100 ms 计算一次当前行，顶栏扩展
每 100 ms 读取一次输出文件。

如果某些歌整体偏快或偏慢，可以加一个全局偏移：

```sh
# 正数：歌词提前（显示更早）
MPRIS_LYRICS_OFFSET_MS=100

# 负数：歌词延后（显示更晚）
MPRIS_LYRICS_OFFSET_MS=-100
```

可以写进 systemd 服务：

```ini
Environment=MPRIS_LYRICS_OFFSET_MS=100
```

然后重启：

```sh
systemctl --user daemon-reload
systemctl --user restart mpris-lyrics.service
```

## 简繁显示

默认根据系统语言自动处理：

- `zh_CN` / `zh_SG`：歌词和歌名显示为简体
- `zh_TW` / `zh_HK` / `zh_MO`：保留歌词/歌名原文（通常为繁体）
- 其他语言：保留原文

也可以手动指定：

```sh
# 强制简体
MPRIS_LYRICS_CHINESE_SCRIPT=simplified

# 保留歌词原文
MPRIS_LYRICS_CHINESE_SCRIPT=original
```

写进 systemd：

```ini
Environment=MPRIS_LYRICS_CHINESE_SCRIPT=simplified
```

## 工作原理

```text
播放器 --MPRIS/D-Bus--> mpris-lyrics-pipe --当前歌词行--> /tmp/mpris-lyrics
                              |                            |
                              |                            +--> GNOME 顶栏扩展
                              |
                              +--> 本地 .lrc / 在线歌词源
```

- 播放信息（歌名、歌手、进度、暂停状态）全部来自本地 MPRIS。
- 自动检测所有音乐类 MPRIS 播放器：优先跟随正在播放的那个；在别的 App 里
  点播放会自动切换过去。浏览器永远不会被选中，也不会抢走当前音乐播放器。
- 所有歌词源都会参与评分，综合得分最高的候选胜出；没有合格候选时
  不会强行使用错误版本，播放中显示 `♫`。
- 在暂停/停止/切歌时更新状态栏，避免显示上一首或暂停时的旧歌词。
- 间奏或空歌词行会保留上一句，直到下一句出现；开头或没有匹配到歌词时
  显示歌曲名字。
- 点击顶栏歌词会打开菜单，里面有 **Settings** 入口。
- 全程不使用第三方音乐服务的 Web API，不需要开发者账号、Client ID/Secret
  或登录步骤。

安装脚本优先把管道注册为 systemd 用户服务 `mpris-lyrics.service`。这样它以
`unconfined` 身份运行，可以读取某些受到 AppArmor 限制的 snap 播放器；如果
手动从受限沙箱里启动，可能会被拒绝访问。

```sh
systemctl --user status mpris-lyrics.service
systemctl --user restart mpris-lyrics.service
cat /tmp/mpris-lyrics
gnome-extensions info mpris-lyrics@gnome-shell-extension
```

## 第三方说明

在线歌词接口和繁简转换数据的来源与许可证说明见
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)。

歌词版权归各音乐平台及权利人所有，本项目只做播放时的歌词展示。

## 卸载

```sh
rm ~/.local/bin/mpris-lyrics-pipe
rm -rf ~/.local/share/mpris-lyrics
rm ~/.config/autostart/mpris-lyrics.desktop
rm -f ~/.config/systemd/user/mpris-lyrics.service
systemctl --user daemon-reload
rm -rf ~/.local/share/gnome-shell/extensions/mpris-lyrics@gnome-shell-extension
rm -f ~/.local/share/glib-2.0/schemas/org.gnome.shell.extensions.mpris-lyrics.gschema.xml
glib-compile-schemas ~/.local/share/glib-2.0/schemas 2>/dev/null || true
```

如果安装时使用了自定义 `PREFIX`，schema 路径对应为
`$PREFIX/share/glib-2.0/schemas/`。
