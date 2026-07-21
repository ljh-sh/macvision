# macvision

[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/ljh-sh/macvision/badge)](https://scorecard.dev/)
[![CI](https://github.com/ljh-sh/macvision/actions/workflows/ci.yml/badge.svg)](https://github.com/ljh-sh/macvision/actions/workflows/ci.yml)
[![Docs](https://img.shields.io/badge/Docs-website-blue.svg)](https://macvision.ljh.sh)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE.txt)

> 把任意图像变成 agent 友好的 JSON —— macOS 本地 OCR 与图像理解。

**macvision** 把 Apple 的 `Vision` 框架封装成一个极小的 Swift 二进制。指向截图、照片或扫描件，拿回文字、场景标签、检测到的人脸 / 条码 / 文档 —— 全部是紧凑 JSON，全部在你的 Mac 上处理。无需下载大模型，不上传任何数据。在那些原本要调用 LLM vision 的地方改用它：本地免费 OCR，再把文本喂给模型即可。

English: [README.md](README.md)。

## 亮点

- **无需下载大模型** —— 直接跑在 Apple 系统 `Vision` 框架上，无需下载、缓存或加载。
- **省下 LLM vision 费用** —— OCR 与检测全在本地免费完成；把文本喂给模型，而不是按图付费。
- **保护隐私，不上传任何数据** —— 每张图都在你的 Mac 本地处理。
- **agent 友好的 JSON** —— 紧凑单行输出 + FIFO 守护进程，直接嵌入 `jq` 管道和 agent 循环。
- **完整覆盖 Vision 能力** —— OCR、分类、人脸 / 条码 / 文档检测、文档版面、显著性热力图、图像指纹。

文档：[macvision.ljh.sh](https://macvision.ljh.sh)

## 给 AI 智能体

把下面这行 prompt 贴进 Claude Code、Cursor 或任意智能体的系统提示词：

```md
Use `macvision` to read images on macOS (OCR, classify, detect). Install if missing: `brew install ljh-sh/cli/macvision`. JSON output, check `ok`. Run `macvision --help` for subcommands.
```

智能体最经典的循环 —— *截图 → 读图 → 推理* —— 变成一条管道：

```sh
screencapture -i /tmp/s.png
macvision ocr /tmp/s.png --lang zh-Hans,en-US | jq -r '.texts[].text'
```

## 安装

### Homebrew（推荐）

```sh
brew install ljh-sh/cli/macvision
```

或先 tap：

```sh
brew tap ljh-sh/cli
brew install macvision
```

### 直接下载二进制

```sh
curl -L https://github.com/ljh-sh/macvision/releases/latest/download/macvision-darwin-universal.tar.xz | tar xJ -
sudo mv bin/macvision /usr/local/bin/
```

`universal` 包是 fat Mach-O（arm64 + x86_64），Apple Silicon 和 Intel Mac 都能用。

### 从源码构建

需要 Swift 5.10+ / macOS 13+。

```sh
git clone https://github.com/ljh-sh/macvision
cd macvision
swift build -c release
```

## 用法

```sh
# === OCR / 读图 ===
macvision ocr ./screenshot.png                       # 提取文字（默认 TSV：text, confidence, bbox, norm, center）
macvision ocr ./screenshot.png --json                 # JSON 含完整位置
macvision ocr ./screenshot.png --text                 # 一行一个文本
macvision ocr ./screenshot.png --lines                # 按行分组
macvision ocr ./screenshot.png --lang zh-Hans,en-US   # 中英文
macvision ocr -                                       # 从 stdin 读 base64
macvision ocr --clipboard                             # OCR 剪贴板

# === 分类（"这是啥？"）===
macvision classify ./photo.jpg --top 5                # 场景 / 物体标签
macvision classify ./photo.jpg --animals              # 动物物种
macvision classify ./photo.jpg --min-confidence 0.3   # 过滤低置信度

# === 检测：人脸 / 条码 / 矩形 / 文字区域 / 地平线 ===
macvision detect ./photo.jpg                          # 人脸 / 条码 / 文字区域 / 地平线
macvision detect ./shot.png --ocr --lang zh-Hans,en-US  # 全部 + 读出文字
macvision detect ./card.jpg --rects                   # 文档 / 卡片矩形
macvision detect ./qr.png --barcodes --symbologies qr # 仅条码 / QR
macvision detect ./tilted.jpg --horizon               # 倾角检测 / 校正

# === 人脸 / 人体（Apple Vision 内置，无需模型下载）===
macvision face-landmarks ./group.jpg                  # 人脸 + 13 个五官区域（眼 / 鼻 / 嘴 等）
macvision pose ./runner.jpg                           # 每个人体 18 个关节关键点
macvision humans ./meeting.jpg                        # 数人数 / 取人体框

# === 文档 / 显著性 ===
macvision document ./scan.jpg                         # 文档轮廓（用于裁剪 / 纠偏）
macvision salient ./photo.jpg --output heat.png       # 视觉显著性热力图
macvision salient ./photo.jpg --mode objectness       # 物体显著区域

# === 图像相似度 / 检索 ===
macvision feature ./a.jpg                             # 图像指纹向量
macvision feature ./a.jpg --compare ./b.jpg           # 距离（0 = 相同）
macvision feature ./a.jpg --level 2                    # 更精细（macOS 14+）

# === 其他 ===
macvision doctor                                      # 列出支持的 Vision 请求
macvision infer squeezenet1-1 ./photo.jpg              # 试验 CoreML 模型（首次使用时下载）
```

图像输入支持：文件路径、`-`（从 stdin 读 base64）、或 `--clipboard` / `--screen`（读剪贴板 / 现截一张屏）。

默认输出 JSON：

```json
{"ok":true,"image":"./screenshot.png","width":1920,"height":1080,"languages":["zh-Hans","en-US"],"count":3,"texts":[{"text":"你好世界","confidence":0.97,"bbox":[60,495,515,30],"norm":[0.05,0.77,0.43,0.05]}]}
```

边界框是像素坐标 `[x, y, w, h]`，原点在图像**左上角**（智能体映射屏幕坐标所需的约定）。`norm` 是同样的框归一化到 `[0,1]`。

## 给 AI 智能体的速用例子

```sh
# "这张截图写了啥？"
macvision ocr shot.png --tsv

# "这张图是啥？"
macvision classify photo.jpg --top 5 | jq -r '.labels[].name'

# "读一下剪贴板里的 QR 码"
macvision detect --clipboard --barcodes

# "找合影里所有脸"
macvision detect group.jpg --faces

# "会议室里有几个人？"
macvision humans meeting.jpg | jq '.count'

# "这两张图是不是同一张？"
macvision feature a.jpg --compare b.jpg | jq '.distance'

# "画面里最该看哪里？"
macvision salient photo.jpg --output heat.png

# "把所有文字连坐标给我"
macvision ocr shot.png | jq '.texts[] | {text,bbox}'
```

## FIFO 守护进程

需要大量视觉调用的智能体，可以用 `macvision daemon` 常驻框架，通过命名管道处理请求（无 HTTP、无端口）：

```sh
macvision daemon --req /tmp/macvision.req --res /tmp/macvision.res &
echo '{"action":"ocr","image":"/tmp/s.png","lang":["zh-Hans","en-US"]}' > /tmp/macvision.req
cat /tmp/macvision.res   # 每个请求一行 NDJSON 响应
```

请求 schema 见 [docs/subcommands.md](docs/subcommands.md)。

## FAQ

详见 [docs/faq.md](docs/faq.md) 或 [在线 FAQ](https://macvision.ljh.sh/faq)，涵盖权限、截屏、坐标约定，以及 macvision 与 Tesseract / 云端 OCR 的对比。

## 设计

- **小表面**：`ocr`、`classify`、`detect`、`salient`、`document`、`feature`、`daemon`、`doctor`。
- **JSON 输出**：紧凑单行 JSON，方便 `jq` 处理。
- **无 run loop**：`Vision` 的 `perform(_:)` 是同步的，所以 macvision 处理图像时**不**像音频工具那样启动 `NSApplication`。
- **FIFO IPC**：守护进程用命名管道传 NDJSON，匹配周边工具链的 shell 原生风格。

详见 [CONTRIBUTING.md](CONTRIBUTING.md) 和 [ROADMAP.md](ROADMAP.md)。

## 安全

漏洞报告见 [SECURITY.md](SECURITY.md)。

## 许可

Apache-2.0
