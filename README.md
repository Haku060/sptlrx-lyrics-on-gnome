# sptlrx Lyrics Package

终端歌词显示 — 自动同步 Spotify 歌词到 GNOME 顶栏。

## 安装

```sh
chmod +x install.sh
./install.sh
```

可选自定义：

```sh
PREFIX=/usr/local PIPE_PATH=/tmp/my-lyrics ./install.sh
```

## 包含

| 文件 | 说明 |
|------|------|
| `sptlrx` | 歌词同步 CLI (v1.3.1) |
| `sptlrx-pipe` | Python 管道脚本 — 检测切歌/暂停自动清空 |
| `sptlrx-pipe.desktop` | 登录自启 |

## 使用前提

1. Spotify 开发者账号 + App (Client ID / Secret)
2. 运行 `sptlrx login` 登录一次
3. GNOME Executor 扩展: `cat /tmp/sptlrx-lyrics`, 间隔 1s

## 卸载

```sh
rm ~/.local/bin/sptlrx ~/.local/bin/sptlrx-pipe
rm ~/.config/autostart/sptlrx-pipe.desktop
```
