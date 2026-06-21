# macvision

[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/ljh-sh/macvision/badge)](https://scorecard.dev/)
[![CI](https://github.com/ljh-sh/macvision/actions/workflows/ci.yml/badge.svg)](https://github.com/ljh-sh/macvision/actions/workflows/ci.yml)
[![Docs](https://img.shields.io/badge/Docs-website-blue.svg)](https://ljh-sh.github.io/macvision)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE.txt)

> 私密的 macOS 视觉 CLI —— 本地 OCR、图像分类与目标检测，系统占用极低。

**macvision** 把 Apple 的 `Vision` 框架封装成一个极小的 Swift 二进制。它能从截图、照片里提取文字，给图像做场景分类，检测人脸 / 条码 / 文字区域 / 文档边框 —— 全部在你的 Mac 本地完成，无需下载任何模型。所有输出都是紧凑 JSON，方便管道和 AI 智能体使用。

English: [README.md](README.md)。

## 亮点

- **默认私密** —— 图像由 Apple `Vision` 框架在本地处理，不上传任何数据。
- **零模型下载** —— 直接用系统框架，没有模型要下载、缓存或加载。
- **JSON 优先** —— 每个命令都输出紧凑 JSON，方便管道和智能体解析。
- **完整覆盖 Vision 能力** —— OCR、场景 / 动物分类、人脸 / 条码 / 矩形 / 文字检测、文档版面、视觉显著性热力图、图像指纹。

文档：[ljh-sh.github.io/macvision](https://ljh-sh.github.io/macvision)

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
macvision ocr ./screenshot.png                       # 提取文字
macvision ocr ./screenshot.png --lang zh-Hans,en-US   # 中英文
macvision ocr -                                       # 从 stdin 读 base64 图像

macvision classify ./photo.jpg --top 5                # 场景 / 物体标签
macvision classify ./photo.jpg --animals              # 动物物种

macvision detect ./photo.jpg                          # 人脸 / 条码 / 文字区域 / 地平线
macvision detect ./card.jpg --rects                   # 文档 / 卡片矩形
macvision detect ./qr.png --barcodes --symbologies qr # 仅条码 / QR

macvision document ./scan.jpg                         # 文档边框（用于裁剪 / 纠偏）
macvision salient ./photo.jpg                         # 显著性热力图 PNG
macvision feature ./a.jpg                             # 图像指纹向量
macvision feature ./a.jpg --compare ./b.jpg           # 两张图的距离
macvision doctor                                      # 环境与能力检查
```

图像输入支持：文件路径、`-`（从 stdin 读 base64）、或 `--clipboard` / `--screen`（读剪贴板 / 现截一张屏）。

默认输出 JSON：

```json
{"ok":true,"image":"./screenshot.png","width":1920,"height":1080,"languages":["zh-Hans","en-US"],"count":3,"texts":[{"text":"你好世界","confidence":0.97,"bbox":[60,495,515,30],"norm":[0.05,0.77,0.43,0.05]}]}
```

边界框是像素坐标 `[x, y, w, h]`，原点在图像**左上角**（智能体映射屏幕坐标所需的约定）。`norm` 是同样的框归一化到 `[0,1]`。

## FIFO 守护进程

需要大量视觉调用的智能体，可以用 `macvision daemon` 常驻框架，通过命名管道处理请求（无 HTTP、无端口）：

```sh
macvision daemon --req /tmp/macvision.req --res /tmp/macvision.res &
echo '{"action":"ocr","image":"/tmp/s.png","lang":["zh-Hans","en-US"]}' > /tmp/macvision.req
cat /tmp/macvision.res   # 每个请求一行 NDJSON 响应
```

请求 schema 见 [docs/subcommands.md](docs/subcommands.md)。

## FAQ

详见 [docs/faq.md](docs/faq.md) 或 [在线 FAQ](https://ljh-sh.github.io/macvision/faq)，涵盖权限、截屏、坐标约定，以及 macvision 与 Tesseract / 云端 OCR 的对比。

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
