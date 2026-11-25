# DeepSeek Android / Cross-Platform Client (Flutter)

基于官方开源前端 [deepseek-ai/chat-demo](https://github.com/deepseek-ai/chat-demo) 完整复刻的 DeepSeek 移动端客户端（Flutter，Android 优先适配）。无需独立后端，客户端直连 DeepSeek 官方「全家桶应用 API」。

## 核心功能

- **官方原版视觉与交互**：1:1 复刻 DeepSeek 极简蓝白 / 深色双主题（支持浅色 / 深色 / 跟随系统）、中英双语（`简体中文` / `English`）与移动端布局。
- **完整流式对话与深度思考**：
  - 兼容 DeepSeek Anthropic Messages API (`/anthropic/v1/messages`) 与扩展字段（`thinking`、`tools`、`safety_check`、`title`、`latest_reminder`）。
  - 规范 WHATWG SSE 解析器，支持流式输出、停止生成、超长/中断后「继续生成」续写、自动生成会话标题。
  - 可折叠深度思考过程，展示实时思考用时与脉冲步骤时间轴。
- **智能联网搜索与链接阅读**：
  - 内置 `deepseek_web_search` 与 `deepseek_read_url` 工具调用展示（搜索关键词、浏览页面、页内查找、阅读链接）。
  - 行内可点击 `[citation:N]` 引用角标、引用预览弹窗与全屏「搜索结果」来源列表。
- **附件与多模态图片输入**：
  - 支持相册多选、相机拍照及文档选择（支持官方 979 种扩展名白名单、64MB/32MB 大小校验、最多 50 附件、3 并发上传队列）。
  - 自动在后台 Isolate 缩放超长边 > 4096px 的上传图片（本地仍保留原图），并在 `file_id` 失效时自动回填重传。
- **消息分支树与会话管理**：
  - 完整树状分支数据结构：支持编辑历史提问、重新生成回复与 `< 1 / N >` 版本分支切换。
  - SQLite 本地持久化、按时间分组的侧边抽屉（今天 / 昨天 / 7 天内 / 30 天内 / `YYYY-MM`）、行内重命名与引用计数附件清理。
- **原生低延迟语音交互（ASR & TTS）**：
  - Android 原生 `AudioRecord` 录制 16kHz 单声道 16-bit PCM WAV（最长 120 秒），实时 40 频段对数声谱动画，对接 `/v1/tools/asr`。
  - Android 原生 `AudioTrack` 流式播放 `/v1/tools/tts` 返回的 24kHz 原始 PCM 字节流（支持海星女声 `stella` / 暗潮男声 `tide`），搭配动态声波条。
- **Markdown / 公式 / 图表 / 代码高亮**：
  - 自定义 Markdown AST 渲染：禁用 4 空格缩进代码块与 `~` 删除线误伤，支持 GFM 表格与任务列表。
  - `flutter_math_fork` 离线渲染行内/块级 KaTeX 数学公式（流式未闭合时自动回退源码不崩溃）。
  - Atom One Light / Coldark Dark 语法高亮代码块与一键复制。
  - Mermaid 图表块支持「图表 / 代码」切换与 WebView 渲染。
- **DeepSeek 历史记录 ZIP 导入/导出**：
  - 兼容 DeepSeek 官方 v3 导出格式（`manifest.json`、`chat_session_index.json`、`chat_sessions/{id}.json` 及原图附件），支持原子替换导入与分享导出 `deepseek_data-YYYY-MM-DD.zip`。

## 本地构建

环境要求：Flutter 3.50+ / Dart 3.14+ / JDK 17+ / Android SDK 35+。

```bash
# 安装依赖
flutter pub get

# 运行协议与备份单元测试
flutter test

# 构建 Android Debug APK
flutter build apk --debug

# 构建 Android Release APK
flutter build apk --release
```

## 目录结构

```text
android/app/src/main/kotlin/com/witchklee/deepseek_chat/
  MainActivity.kt              # 原生 AudioRecord (16kHz WAV + 声谱) & AudioTrack (24kHz PCM 流式播放)
lib/
  data/                        # 官方 979 附件扩展名白名单、全国省市与 249 国家地区数据
  l10n/                        # 中英双语词条
  models/                      # API 协议、SSE 事件、会话分支与 ReplyView 模型
  providers/                   # SettingsProvider, ChatProvider, SpeechProvider
  screens/                     # HomeScreen 主界面
  services/
    api/                       # SSE 解码、事件解析、DeepSeekClient、错误分类
    chat/                      # 分支树、上下文组装、latest_reminder、时间轴派生、会话分组
    speech/                    # 原生音频 PlatformChannel 封装
    storage/                   # SQLite 存储、图片缩放、DeepSeek v3 ZIP 导入导出
  theme/                       # DeepSeek Light/Dark 语义色板与官方矢量图标
  widgets/                     # Header、Drawer、Composer、消息气泡、Markdown/KaTeX/Mermaid、搜索面板、设置弹窗
```
