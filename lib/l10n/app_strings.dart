/// Complete zh-CN and en-US localization strings ported from deepseek-ai/chat-demo.
class AppStrings {
  final bool isZh;

  const AppStrings(this.isZh);

  static AppStrings of(String locale) => AppStrings(locale.startsWith('zh'));

  String get appName => 'DeepSeek';
  String get untitledChat => isZh ? '新对话' : 'New chat';
  String get newChat => isZh ? '开启新对话' : 'New chat';
  String get welcomeGreeting => isZh ? '今天有什么可以帮到你？' : 'How can I help you?';
  String get inputPlaceholder => isZh ? '请输入消息' : 'Enter a message';
  String get caveat => isZh ? '内容由 AI 生成，请仔细甄别' : 'AI-generated, for reference only';

  // Composer toggles
  String get deepThink => isZh ? '深度思考' : 'DeepThink';
  String get smartSearch => isZh ? '智能搜索' : 'Search';
  String get continueGenerating => isZh ? '继续生成' : 'Continue';

  // Drawer & Session groups
  String get today => isZh ? '今天' : 'Today';
  String get yesterday => isZh ? '昨天' : 'Yesterday';
  String get within7Days => isZh ? '7 天内' : '7 Days';
  String get within30Days => isZh ? '30 天内' : '30 Days';
  String get rename => isZh ? '重命名' : 'Rename';
  String get delete => isZh ? '删除' : 'Delete';
  String get cancel => isZh ? '取消' : 'Cancel';
  String get confirm => isZh ? '确定' : 'Confirm';
  String get send => isZh ? '发送' : 'Send';
  String get retry => isZh ? '重试' : 'Retry';
  String get settings => isZh ? '设置' : 'Settings';

  // Delete session dialog
  String get deleteChatTitle => isZh ? '永久删除对话' : 'Delete chat?';
  String get deleteChatDesc => isZh
      ? '该对话及其上传的文件将被永久删除且无法恢复，确认删除吗？'
      : 'This chat and its uploaded files will be permanently deleted and cannot be recovered. Delete this chat?';
  String get deleteSuccess => isZh ? '删除成功' : 'Successfully deleted.';

  // Thinking & Search steps
  String get thinking => isZh ? '正在思考' : 'Thinking';
  String get searchingWeb => isZh ? '正在搜索' : 'Searching the web';
  String get searchingByImage => isZh ? '图像搜索中...' : 'Searching by image...';
  String get browsingWeb => isZh ? '正在浏览网页' : 'Browsing the web';
  String get readingLink => isZh ? '正在阅读' : 'Reading';
  String get stopped => isZh ? '已停止' : 'Stopped';
  String get deepThinkDoneFallback => isZh ? '深度思考' : 'DeepThink';
  String thoughtForSeconds(int s) =>
      isZh ? '已思考（用时 $s 秒）' : 'Thought for $s ${s == 1 ? 'second' : 'seconds'}';
  String get searchingFor => isZh ? '正在搜索' : 'Searching for';
  String get searchingEllipsis => isZh ? '正在搜索...' : 'Searching...';
  String get searchStopped => isZh ? '搜索已停止' : 'Search stopped';
  String get searchUnavailable => isZh ? '联网搜索暂不可用' : 'Search currently unavailable';
  String get noSuitableResults => isZh ? '未找到合适的结果' : 'No suitable results found';
  String get noRelevantResults => isZh ? '未找到相关结果' : 'No relevant results found';
  String foundWebPages(int n) => isZh ? '找到 $n 个网页' : 'Found $n web ${n == 1 ? 'page' : 'pages'}';
  String readWebPages(int n) => isZh ? '已阅读 $n 个网页' : 'Read $n web ${n == 1 ? 'page' : 'pages'}';
  String webPagesCount(int n) => isZh ? '$n 个网页' : '$n web ${n == 1 ? 'page' : 'pages'}';
  String readPages(int n) => isZh ? '浏览 $n 个页面' : 'Read $n ${n == 1 ? 'page' : 'pages'}';
  String get viewAll => isZh ? '查看全部' : 'View All';
  String get findKeyword => isZh ? '查找关键词' : 'Find keyword';
  String get searchResults => isZh ? '搜索结果' : 'Search results';

  // Code & Mermaid
  String get copy => isZh ? '复制' : 'Copy';
  String get copied => isZh ? '已复制' : 'Copied';
  String get diagram => isZh ? '图表' : 'Diagram';
  String get code => isZh ? '代码' : 'Code';
  String get renderingDiagram => isZh ? '正在渲染图表...' : 'Rendering diagram...';
  String get emptyDiagram => isZh ? '当前图表为空。' : 'This diagram is empty.';
  String get mermaidFailed => isZh ? 'Mermaid 图表渲染失败。' : 'Mermaid rendering failed.';

  // Settings
  String get generalSettings => isZh ? '通用设置' : 'General';
  String get dataManagement => isZh ? '数据管理' : 'Data';
  String get theme => isZh ? '主题' : 'Theme';
  String get themeLight => isZh ? '浅色' : 'Light';
  String get themeDark => isZh ? '深色' : 'Dark';
  String get themeSystem => isZh ? '跟随系统' : 'System';
  String get language => isZh ? '语言' : 'Language';
  String get readAloudVoice => isZh ? '朗读音色' : 'Read-aloud voice';
  String get voiceStella => isZh ? '海星（女声）' : 'Stella (female)';
  String get voiceTide => isZh ? '暗潮（男声）' : 'Tide (male)';
  String get location => isZh ? '位置信息' : 'Location';
  String get selectProvince => isZh ? '请选择省份/地区' : 'Select province/region';
  String get selectCity => isZh ? '请选择市' : 'Select city';
  String get selectRegion => isZh ? '请选择国家或地区' : 'Select country or region';
  String get notSet => isZh ? '未设置' : 'Not set';
  String get modelLabel => isZh ? '对话模型' : 'Model';
  String get apiOriginLabel => isZh ? '接口地址 (API Origin)' : 'API Origin';

  // API Key
  String get enterApiKeyHeader => isZh ? '输入 API Key 开始使用' : 'Enter an API Key to get started';
  String get enterApiKeyHint => isZh ? '请输入 API Key' : 'Enter API Key';
  String get verifying => isZh ? '正在验证...' : 'Verifying...';
  String get apiKeySaved => isZh ? 'API Key 已保存' : 'API Key saved';
  String get apiKeyInvalid => isZh ? 'API Key 无效，请检查后重试' : 'Invalid API Key. Please check and try again.';
  String get changeApiKey => isZh ? '修改 API Key' : 'Change API Key';
  String get topUp => isZh ? '去充值' : 'Top up';
  String verifyFailed(String msg) => isZh ? '验证失败：$msg' : 'Verification failed: $msg';

  // Backup / Data
  String get importHistory => isZh ? '导入历史对话' : 'Import chat history';
  String get importHistoryDesc => isZh
      ? '导入历史对话会覆盖本地所有对话与附件。支持从 DeepSeek 导出的 ZIP 文件。'
      : 'Importing chat history replaces all local chats and attachments. Supports ZIP files exported from DeepSeek.';
  String get upload => isZh ? '上传' : 'Upload';
  String get importConfirmTitle => isZh ? '确认导入历史对话？' : 'Import chat history?';
  String get importConfirmDesc => isZh
      ? '导入将替换当前所有本地对话与附件，确定继续吗？'
      : 'Importing will replace all existing local chats and attachments. Continue?';
  String get importAction => isZh ? '导入' : 'Import';
  String importedChats(int n) => isZh ? '已导入 $n 个对话' : 'Imported $n ${n == 1 ? 'chat' : 'chats'}';
  String get exportAllChats => isZh ? '导出所有历史对话' : 'Export all chats';
  String get exportAllChatsDesc => isZh
      ? '包含所有历史对话和本地保存的原始图片，其他附件仅保留文件信息。不包含您的 API Key。'
      : 'Includes all chat history and locally stored images. Other attachments retain file details only. Your API Key is not included.';
  String get download => isZh ? '下载' : 'Download';
  String get exportSuccess => isZh ? '导出成功' : 'Export complete';
  String get deleteAllChats => isZh ? '删除所有对话' : 'Delete all chats';
  String get deleteAllConfirmTitle => isZh
      ? '删除后所有对话将被清空且无法恢复。'
      : 'Once deleted, all chats will be cleared and cannot be recovered.';
  String get deleteAllConfirmDesc => isZh
      ? '本地保存的附件与未发送的草稿也会一并删除。'
      : 'Locally saved attachments and unsent drafts will also be deleted.';
  String get deleting => isZh ? '正在删除...' : 'Deleting...';

  // Backup errors
  String get backupInvalidZip => isZh ? '所选文件不是有效的 ZIP 压缩包' : 'Selected file is not a valid ZIP archive.';
  String get backupNewerVersion => isZh ? '备份版本过高，请更新客户端后再导入' : 'Backup format version is newer than supported.';
  String get backupInvalidVersion => isZh ? '不支持的备份格式版本' : 'Unsupported backup format version.';
  String get backupIncomplete => isZh ? '备份文件不完整或格式已损坏' : 'Backup archive is incomplete or corrupted.';
  String get backupInvalidFiles => isZh ? '备份中的附件路径无效' : 'Backup contains invalid attachment paths.';

  // Attachments & Picker
  String get pickImage => isZh ? '相册图片' : 'Photos';
  String get takePhoto => isZh ? '拍照' : 'Camera';
  String get pickFile => isZh ? '选择文件' : 'Files';
  String get unsupportedFileType => isZh ? '不支持该文件格式' : 'Unsupported file format';
  String fileTooLarge(int maxMb) => isZh ? '文件大小不能超过 $maxMb MB' : 'File size must not exceed $maxMb MB';
  String get tooManyFiles => isZh ? '最多只能上传 50 个附件' : 'Up to 50 attachments allowed';
  String get uploadFailed => isZh ? '上传失败' : 'Upload failed';
  String get parseFailed => isZh ? '文件解析失败' : 'Failed to parse file';
  String fileCountLimit(String limit) => isZh ? '账户文件数已达上限 ($limit)' : 'Account file count limit exceeded ($limit)';
  String storageLimit(String limit) => isZh ? '账户存储空间已达上限 ($limit GB)' : 'Account storage quota exceeded ($limit GB)';
  String get waitUploads => isZh ? '请等待附件上传完成' : 'Please wait for attachments to finish uploading';

  // Speech (ASR / TTS)
  String get micPermissionDenied => isZh ? '请授予麦克风权限以使用语音输入' : 'Microphone permission is required for voice input';
  String get recordingLimitReached => isZh ? '单次录音最长 120 秒，已自动停止' : 'Reached the 120s recording limit';
  String get asrFailed => isZh ? '语音识别失败，请重试' : 'Speech recognition failed';
  String get asrEmpty => isZh ? '未识别到有效语音内容' : 'No speech detected';
  String get ttsUnavailable => isZh ? '当前内容暂不支持朗读' : 'This content cannot be read aloud';
  String get ttsFailed => isZh ? '语音朗读失败' : 'Read-aloud failed';

  // Reply notices & API errors
  String get replyRefused => isZh
      ? '你好，这个问题我暂时无法回答，让我们换个话题再聊聊吧。'
      : "Sorry, that's beyond my current scope. Let's talk about something else.";
  String get replyInvalidApiKey => isZh
      ? 'API Key 无效或已被删除，请重新配置。'
      : 'The API Key is invalid or has been deleted.';
  String get replyInsufficientBalance => isZh
      ? '账户余额不足，请充值后再试。'
      : 'Insufficient account balance. Please top up to continue.';
  String get replyRateLimited => isZh ? '请求过于频繁，请稍后再试。' : 'Too many requests. Please try again later.';
  String get serverBusy => isZh ? '服务器繁忙，请稍后再试。' : 'Server busy, please try again later.';
  String get networkError => isZh ? '网络异常，请检查网络连接。' : 'Network Error. Please check your network status.';
  String get requestTooLarge => isZh ? '请求内容过大，请精简后重试。' : 'Request is too large. Please shorten it and try again.';
  String get sessionSaveFailed => isZh ? '对话保存失败' : 'Failed to save chat';
}
