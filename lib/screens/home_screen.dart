import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/chat_models.dart';
import '../providers/chat_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/speech_provider.dart';
import '../theme/ds_icons.dart';
import '../theme/ds_theme.dart';
import '../widgets/chat/assistant_message_widget.dart';
import '../widgets/chat/chat_composer.dart';
import '../widgets/chat/mobile_header.dart';
import '../widgets/chat/search_panel.dart';
import '../widgets/chat/user_message_widget.dart';
import '../widgets/settings/settings_sheet.dart';
import '../widgets/sider/chat_drawer.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollController = ScrollController();
  bool _followBottom = true;
  bool _promptedInitialApiKey = false;
  int _lastMsgCount = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final settings = context.read<SettingsProvider>();
    final chat = context.read<ChatProvider>();
    await settings.load();
    await chat.init();
    if (mounted && !settings.hasApiKey && !_promptedInitialApiKey) {
      _promptedInitialApiKey = true;
      showDsSettingsSheet(context, initialTab: SettingsTab.data);
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final distFromBottom = pos.maxScrollExtent - pos.pixels;
    _followBottom = distFromBottom <= 48;
  }

  void _scrollToBottomIfFollowing() {
    if (!_followBottom || !_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final settingsProv = context.watch<SettingsProvider>();
    final s = settingsProv.strings;
    final chat = context.watch<ChatProvider>();
    final session = chat.activeSession;
    final messages = chat.visibleMessages;
    final versions = chat.messageVersions;
    final isWelcome = session == null;

    if (messages.length != _lastMsgCount) {
      _lastMsgCount = messages.length;
      _followBottom = true;
    }
    if (chat.isActiveSessionStreaming) {
      _scrollToBottomIfFollowing();
    }

    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: ds.isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: ds.isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness:
          ds.isDark ? Brightness.light : Brightness.dark,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Stack(
        children: [
          Scaffold(
            key: _scaffoldKey,
            backgroundColor: ds.bgBase,
          drawer: ChatDrawer(
            onOpenSettings: () => showDsSettingsSheet(
              context,
              initialTab: SettingsTab.general,
            ),
          ),
          body: SafeArea(
            child: Column(
              children: [
                // Optional save-error bar matching App.tsx
                if (chat.saveFailed)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    color: ds.errorPrimary.withValues(alpha: 0.08),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 16,
                          color: ds.errorPrimary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            s.sessionSaveFailed,
                            style: TextStyle(
                              fontSize: 13,
                              color: ds.errorPrimary,
                            ),
                          ),
                        ),
                        OutlinedButton(
                          onPressed: chat.retrySave,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: ds.errorPrimary,
                            side: BorderSide(color: ds.errorPrimary),
                            minimumSize: const Size(0, 28),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            shape: const StadiumBorder(),
                          ),
                          child: Text(s.retry,
                              style: const TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ),

                // Mobile Header
                MobileHeader(
                  title: session?.title,
                  showSessionControls: !isWelcome && !chat.loading,
                  strings: s,
                  onOpenDrawer: () {
                    FocusScope.of(context).unfocus();
                    _scaffoldKey.currentState?.openDrawer();
                  },
                  onNewChat: () {
                    context.read<SpeechProvider>().stopReadAloud();
                    chat.newChat();
                  },
                ),

                // Content area (Loading / Welcome / Session Thread)
                Expanded(
                  child: chat.loading
                      ? Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: ds.brandPrimary,
                          ),
                        )
                      : isWelcome
                          ? _buildWelcomeBody(ds, s.welcomeGreeting)
                          : _buildMessageList(chat, messages, versions, s),
                ),

                // Bottom Composer + Caveat
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: ChatComposer(
                    isWelcome: isWelcome,
                    onNeedApiKey: () => showDsSettingsSheet(
                      context,
                      initialTab: SettingsTab.data,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    s.caveat,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      height: 16 / 11,
                      color: ds.labelTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Full-screen SearchPanel overlay
        if (chat.searchPanelSources != null)
          Positioned.fill(
            child: SearchResultsSheet(
              sources: chat.searchPanelSources!,
              strings: s,
              onClose: chat.closeSearchPanel,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeBody(DsColors ds, String greeting) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.translucent,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DsIcons.whaleLogo(size: 46, color: ds.brandPrimary),
              const SizedBox(height: 14),
              Text(
                greeting,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  height: 30 / 22,
                  fontWeight: FontWeight.w600,
                  color: ds.labelPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageList(
    ChatProvider chat,
    List<ChatMessage> messages,
    Map<String, MessageVersionInfo> versions,
    dynamic s,
  ) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.translucent,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        itemCount: messages.length,
        itemBuilder: (ctx, i) {
          final msg = messages[i];
          final version = versions[msg.id];
          final isLast = i == messages.length - 1;

          if (msg is UserMessage) {
            return UserMessageWidget(
              key: ValueKey(msg.id),
              message: msg,
              version: version,
              busy: chat.isStreaming,
              strings: s,
              onEdit: (newText) => chat.editUserMessage(msg.id, newText),
              onSelectVersion: (id) => chat.selectMessageVersion(id),
            );
          }

          if (msg is AssistantMessage) {
            return AssistantMessageWidget(
              key: ValueKey(msg.id),
              message: msg,
              version: version,
              isLast: isLast,
              busy: chat.isStreaming,
              strings: s,
              onRegenerate: () => chat.regenerateReply(msg.id),
              onContinue: () => chat.continueReply(msg.id),
              onSelectVersion: (id) => chat.selectMessageVersion(id),
              onOpenSearchPanel: chat.openSearchPanel,
              onOpenApiKeySettings: () => showDsSettingsSheet(
                context,
                initialTab: SettingsTab.data,
              ),
            );
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }
}
