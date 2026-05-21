# WorldTV 字幕服务器

在 Mac 上运行,为 Apple TV app 提供实时 AI 字幕(语音识别 + 翻译)。
Apple TV 端只负责采集音频和显示字幕,所有 AI 计算都在这里完成。

## 工作原理

```
Apple TV  ──16kHz 单声道 PCM──▶  字幕服务器(本机)
                                  ├─ faster-whisper:任意语言语音 → 英文
                                  └─ argostranslate:英文 → 中文
Apple TV  ◀──字幕文本(JSON)────  服务器
```

## 安装

需要 Python 3.9+。

```bash
cd server
pip3 install -r requirements.txt
```

首次运行会自动下载 Whisper 模型(约 480MB)和英→中翻译包。

## 运行

```bash
python3 subtitle_server.py
```

启动后监听 `ws://0.0.0.0:8765`。在 Apple TV app 的设置里把"字幕服务器地址"
填成这台 Mac 的局域网地址,例如 `ws://192.168.1.20:8765`。

查看本机局域网 IP:

```bash
ipconfig getifaddr en0
```

## 说明

- Mac 和 Apple TV 需在同一局域网。
- 默认用 Whisper `small` 模型;想更准可把 `subtitle_server.py` 里的
  `WHISPER_MODEL` 改成 `medium` 或 `large-v3`(更慢、更吃内存)。
- 服务器需保持运行,Apple TV 才能用 AI 字幕。
