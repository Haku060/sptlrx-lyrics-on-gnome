# sptlrx Lyrics Package

终端歌词显示 — 自动同步本地播放器歌词到 GNOME 顶栏。

**不需要 Spotify 开发者账号。** 播放状态直接从本地 MPRIS（D-Bus）读取，
任何支持 MPRIS 的播放器都可以用：Spotify 桌面版、Rhythmbox、VLC、mpv、
Audacious、Clementine、Strawberry、Firefox / Chromium 等。

## 安装

```sh
chmod +x install.sh
./install.sh
```

可选自定义：

```sh
PREFIX=/usr/local PIPE_PATH=/tmp/my-lyrics ./install.sh
```

默认会自动识别所有 MPRIS 播放器，并优先跟随当前正在播放的那个。比如你同时开着
Spotify、网易云（`open-orpheus`）和浏览器，哪个在播放就用哪个；如果都暂停了，
会保留最后一次使用的播放器。

不会给某个具体 App 设置固定优先级。只有在多个候选同时满足条件时，才按
「新开始播放的音乐播放器 > 当前播放器 > 其他正在播放的播放器」以及
「音乐播放器优先于浏览器」来仲裁。

安装脚本会写入 `~/.config/sptlrx/config.yaml`：

```yaml
player: mpris
mpris:
  players: []          # 空 = 自动识别所有 MPRIS 播放器
```

如果想强制只用一个播放器，可以固定它：

```sh
MPRIS_PLAYER=spotify ./install.sh      # Spotify
MPRIS_PLAYER=open-orpheus ./install.sh # 网易云客户端
MPRIS_PLAYER=rhythmbox ./install.sh    # Rhythmbox
```

其他播放器把值换成 MPRIS 总线名 `org.mpris.MediaPlayer2.<名字>` 的后缀即可。
固定后会写入：

```yaml
mpris:
  players: [spotify]
```

之后也可以手动编辑这个文件。改完重启：

```sh
systemctl --user restart sptlrx-pipe.service
```

**第一次安装后需要重启 GNOME Shell 才会加载顶栏扩展：**

- X11：按 `Alt+F2`，输入 `r`，回车
- Wayland：注销并重新登录

之后顶栏右侧会显示当前歌词行；没有歌词时自动隐藏。

## 包含

| 文件 | 说明 |
|------|------|
| `sptlrx-pipe` | Python 管道脚本 — 读取本地 MPRIS，获取并同步歌词 |
| `gnome-extension/` | GNOME Shell 顶栏扩展 — 每秒读取歌词文件并显示 |
| `data/TSCharacters.txt` | 繁简转换表，用于匹配网易云的简体歌名 |
| `sptlrx` | 可选 TUI 歌词程序（状态栏不需要它） |
| `sptlrx-pipe.desktop` | 无 systemd 时的登录自启 |

## 使用前提

1. 任意支持 MPRIS 的播放器（Spotify 桌面版、网易云 `open-orpheus`、
   Rhythmbox、VLC、mpv、浏览器等），无需登录 Spotify 开发者后台
2. `gdbus`（GLib 自带；Debian/Ubuntu 包名 `libglib2.0-bin`）
3. GNOME Shell 45 / 46 / 47

## 歌词来源

默认顺序是：

1. **本地 `.lrc` 文件**（如果配置了 `local.folder`）
2. **网易云音乐**（搜索 + 歌词接口，和 Lyricify 使用的是同一类公开 eapi 接口）
3. **LRCLIB**（`https://lrclib.net`，作为兜底）

可以用环境变量调整顺序，例如只用网易云：

```sh
SPTLRX_LYRICS_SOURCES=netease systemctl --user restart sptlrx-pipe.service
```

或者写进 systemd 服务：

```ini
Environment=SPTLRX_LYRICS_SOURCES=netease,lrclib
```

本地 `.lrc` 目录可以这样配置：

```yaml
# ~/.config/sptlrx/config.yaml
local:
  folder: ~/Music/lyrics
```

文件名包含歌手和歌名即可，例如：

```text
~/Music/lyrics/張敬軒 - 酷愛.lrc
```

歌曲匹配会先做繁转简（`張敬軒` → `张敬轩`），再结合歌名、歌手和
`mpris:length` 时长来选最接近的网易云结果。

## 工作原理

```
播放器 --MPRIS/D-Bus--> sptlrx-pipe --当前歌词行--> /tmp/sptlrx-lyrics
                              |                            |
                              |                            +--> GNOME 顶栏扩展
                              |
                              +--> 本地 .lrc / 网易云 / LRCLIB
```

- 播放信息（歌名、歌手、进度、暂停状态）全部来自本地 MPRIS。
- 自动检测所有 MPRIS 播放器：优先跟随正在播放的那个；在别的 App 里点播放
  会自动切换过去，浏览器开始播放不会抢走正在播放的音乐。
- 歌词按本地 `.lrc` → 网易云 → LRCLIB 的顺序获取。
- 在暂停/停止/切歌时清空或更新状态栏，避免显示上一首或暂停时的旧歌词。
- 全程不使用 Spotify Web API，不需要 Client ID / Secret，也不需要 `sptlrx login`。

安装脚本优先把管道注册为 systemd 用户服务 `sptlrx-pipe.service`。这样它以
`unconfined` 身份运行，可以读取 **snap 版 Spotify** 的 MPRIS；如果手动从受限
沙箱里启动，AppArmor 可能会拒绝访问 snap Spotify。

```sh
systemctl --user status sptlrx-pipe.service
systemctl --user restart sptlrx-pipe.service
cat /tmp/sptlrx-lyrics
gnome-extensions info sptlrx-lyrics@gnome-shell-extension
```

## 歌词来源说明

- 网易云音乐接口的请求格式参考了
  [WXRIW/Lyricify-Lyrics-Helper](https://github.com/WXRIW/Lyricify-Lyrics-Helper)
  （Apache-2.0）。
- `data/TSCharacters.txt` 来自
  [OpenCC](https://github.com/BYVoid/OpenCC)（Apache-2.0）。
- 歌词版权归各音乐平台及权利人所有，本项目只做播放时的歌词展示。

## 卸载

```sh
rm ~/.local/bin/sptlrx ~/.local/bin/sptlrx-pipe
rm -rf ~/.local/share/sptlrx
rm ~/.config/autostart/sptlrx-pipe.desktop
rm -f ~/.config/systemd/user/sptlrx-pipe.service
systemctl --user daemon-reload
rm -rf ~/.local/share/gnome-shell/extensions/sptlrx-lyrics@gnome-shell-extension
```
