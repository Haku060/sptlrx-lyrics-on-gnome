# MPRIS Lyrics on GNOME

在 GNOME 顶栏显示本地播放器的同步歌词。

> **AI 辅助说明：** 本项目在 AI 辅助下完成，包括代码改造、文档编写和调试。

> **仓库名：** `mpris-lyrics-on-gnome`
>
> 本项目从 [`Haku060/sptlrx-lyrics-on-gnome`](https://github.com/Haku060/sptlrx-lyrics-on-gnome)
> fork 后改造而来。原来的编译产物 `sptlrx` 已经删除；为了兼容已有安装，
> 管道脚本名、配置目录和 GNOME 扩展 UUID 仍然保留 `sptlrx` 前缀。

播放信息全部来自本地 MPRIS（D-Bus），不依赖任何第三方音乐服务账号。
任何支持 MPRIS 的本地播放器都可以使用。

## 安装

```sh
chmod +x install.sh
./install.sh
```

安装脚本会删除旧版本遗留的 `~/.local/bin/sptlrx` 编译二进制；现在状态栏
管道和扩展都不再使用它。

可选自定义：

```sh
PREFIX=/usr/local PIPE_PATH=/tmp/my-lyrics ./install.sh
```

默认会自动识别所有 MPRIS 播放器，并优先跟随当前正在播放的那个。
如果都暂停了，会保留最后一次使用的播放器。

不会给某个具体 App 设置固定优先级。只有在多个候选同时满足条件时，才按
「新开始播放的音乐播放器 > 当前播放器 > 其他正在播放的播放器」以及
「音乐播放器优先于浏览器」来仲裁。

安装脚本会写入 `~/.config/sptlrx/config.yaml`：

```yaml
player: mpris
mpris:
  players: []          # 空 = 自动识别所有 MPRIS 播放器
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
| `data/TSCharacters.txt` | 繁简转换表，用于匹配在线歌词源 |
| `sptlrx-pipe.desktop` | 无 systemd 时的登录自启 |

## 使用前提

1. 任意支持 MPRIS 的本地播放器
2. `gdbus`（GLib 自带；Debian/Ubuntu 包名 `libglib2.0-bin`）
3. GNOME Shell 45 / 46 / 47

## 歌词来源

默认顺序是：

1. **本地 `.lrc` 文件**（如果配置了 `local.folder`）
2. **在线歌词源**
3. **备用在线歌词源**

可以用环境变量调整顺序，具体可用值见 `sptlrx-pipe` 顶部的
`LYRICS_SOURCES`：

```sh
SPTLRX_LYRICS_SOURCES=<source1>,<source2> systemctl --user restart sptlrx-pipe.service
```

也可以写进 systemd 服务：

```ini
Environment=SPTLRX_LYRICS_SOURCES=<source1>,<source2>
```

本地 `.lrc` 目录可以这样配置：

```yaml
# ~/.config/sptlrx/config.yaml
local:
  folder: ~/Music/lyrics
```

文件名包含歌手和歌名即可，例如：

```text
~/Music/lyrics/歌手 - 歌名.lrc
```

歌曲匹配会先做繁转简，再结合歌名、歌手和 `mpris:length` 时长来选择
最接近的在线歌词结果。

## 同步微调

歌词按本地 MPRIS 的播放位置同步。管道每 100 ms 计算一次当前行，顶栏扩展
每 100 ms 读取一次输出文件。

如果某些歌整体偏快或偏慢，可以加一个全局偏移：

```sh
# 正数：歌词提前（显示更早）
SPTLRX_LYRICS_OFFSET_MS=100

# 负数：歌词延后（显示更晚）
SPTLRX_LYRICS_OFFSET_MS=-100
```

可以写进 systemd 服务：

```ini
Environment=SPTLRX_LYRICS_OFFSET_MS=100
```

然后重启：

```sh
systemctl --user daemon-reload
systemctl --user restart sptlrx-pipe.service
```

## 工作原理

```text
播放器 --MPRIS/D-Bus--> sptlrx-pipe --当前歌词行--> /tmp/sptlrx-lyrics
                              |                            |
                              |                            +--> GNOME 顶栏扩展
                              |
                              +--> 本地 .lrc / 在线歌词源
```

- 播放信息（歌名、歌手、进度、暂停状态）全部来自本地 MPRIS。
- 自动检测所有 MPRIS 播放器：优先跟随正在播放的那个；在别的 App 里点播放
  会自动切换过去，浏览器开始播放不会抢走正在播放的音乐。
- 歌词按本地 `.lrc` → 在线歌词源 → 备用在线歌词源的顺序获取。
- 在暂停/停止/切歌时清空或更新状态栏，避免显示上一首或暂停时的旧歌词。
- 全程不使用第三方音乐服务的 Web API，不需要开发者账号、Client ID/Secret
  或登录步骤。

安装脚本优先把管道注册为 systemd 用户服务 `sptlrx-pipe.service`。这样它以
`unconfined` 身份运行，可以读取某些受到 AppArmor 限制的 snap 播放器；如果
手动从受限沙箱里启动，可能会被拒绝访问。

```sh
systemctl --user status sptlrx-pipe.service
systemctl --user restart sptlrx-pipe.service
cat /tmp/sptlrx-lyrics
gnome-extensions info sptlrx-lyrics@gnome-shell-extension
```

## 第三方说明

在线歌词接口和繁简转换数据的来源与许可证说明见
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)。

歌词版权归各音乐平台及权利人所有，本项目只做播放时的歌词展示。

## 卸载

```sh
rm ~/.local/bin/sptlrx-pipe
rm -rf ~/.local/share/sptlrx
rm ~/.config/autostart/sptlrx-pipe.desktop
rm -f ~/.config/systemd/user/sptlrx-pipe.service
systemctl --user daemon-reload
rm -rf ~/.local/share/gnome-shell/extensions/sptlrx-lyrics@gnome-shell-extension
```
