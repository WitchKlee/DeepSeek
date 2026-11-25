import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/chat_models.dart';
import '../../providers/chat_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/chat/session_groups.dart';
import '../../theme/ds_icons.dart';
import '../../theme/ds_theme.dart';
import '../common/ds_modals.dart';
import '../common/ds_toast.dart';

/// Slide-out DeepSeek conversation drawer matching `Sider.tsx` & `SessionItem.tsx`.
class ChatDrawer extends StatefulWidget {
  final VoidCallback onOpenSettings;

  const ChatDrawer({super.key, required this.onOpenSettings});

  @override
  State<ChatDrawer> createState() => _ChatDrawerState();
}

class _ChatDrawerState extends State<ChatDrawer> {
  String? _renamingId;
  final TextEditingController _renameController = TextEditingController();
  final FocusNode _renameFocus = FocusNode();

  @override
  void dispose() {
    _renameController.dispose();
    _renameFocus.dispose();
    super.dispose();
  }

  void _startRename(SessionSummary item, String fallbackTitle) {
    setState(() {
      _renamingId = item.id;
      _renameController.text =
          item.title.isEmpty ? fallbackTitle : item.title;
      _renameController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _renameController.text.length,
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _renameFocus.requestFocus();
    });
  }

  Future<void> _commitRename(String sessionId) async {
    final text = _renameController.text.trim();
    setState(() => _renamingId = null);
    if (text.isNotEmpty && mounted) {
      await context.read<ChatProvider>().renameSession(sessionId, text);
    }
  }

  Future<void> _confirmDelete(SessionSummary item) async {
    final s = context.read<SettingsProvider>().strings;
    final ok = await showDsConfirmDialog(
      context: context,
      title: s.deleteChatTitle,
      body: s.deleteChatDesc,
      cancelText: s.cancel,
      confirmText: s.delete,
      danger: true,
    );
    if (ok && mounted) {
      await context.read<ChatProvider>().deleteSession(item.id);
      if (mounted) DsToast.show(context, s.deleteSuccess);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final s = context.watch<SettingsProvider>().strings;
    final chat = context.watch<ChatProvider>();
    final screenW = MediaQuery.of(context).size.width;
    final drawerW = min(300.0, screenW - 48);
    final groups = groupSessionsByTime(chat.summaries, s);
    final activeId = chat.activeSession?.id;

    return Drawer(
      width: drawerW,
      backgroundColor: ds.sidebarFill,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Brand header
              SizedBox(
                height: 48,
                child: Row(
                  children: [
                    const SizedBox(width: 4),
                    DsIcons.whaleLogo(size: 26, color: ds.brandPrimary),
                    const SizedBox(width: 8),
                    Text(
                      s.appName,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: ds.brandPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const Spacer(),
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        padding: EdgeInsets.zero,
                        icon: DsIcons.svg(
                          DsIcons.panelLeft,
                          size: 16,
                          color: ds.labelSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Elevated New Chat pill button
              GestureDetector(
                onTap: () {
                  chat.newChat();
                  Navigator.of(context).pop();
                },
                child: Container(
                  height: 42,
                  decoration: BoxDecoration(
                    color: ds.buttonElevatedFill,
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                      color: ds.isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : ds.borderL1,
                    ),
                    boxShadow: ds.isDark
                        ? null
                        : [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      DsIcons.svg(
                        DsIcons.newChat,
                        size: 16,
                        color: ds.labelPrimary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        s.newChat,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: ds.labelPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Time-grouped session list
              Expanded(
                child: groups.isEmpty
                    ? Center(
                        child: Text(
                          s.noHistoryChats,
                          style: TextStyle(
                            fontSize: 13,
                            color: ds.labelCaption,
                          ),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.only(bottom: 12),
                        children: [
                          for (final g in groups) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
                              child: Text(
                                g.label,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: ds.labelTertiary,
                                ),
                              ),
                            ),
                            for (final item in g.sessions)
                              _buildSessionRow(
                                context: context,
                                item: item,
                                isActive: item.id == activeId,
                                fallbackTitle: s.untitledChat,
                                ds: ds,
                                renameLabel: s.rename,
                                deleteLabel: s.delete,
                              ),
                          ],
                        ],
                      ),
              ),

              // Footer Settings entry
              Divider(height: 1, color: ds.borderL1),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: InkWell(
                  onTap: () {
                    Navigator.of(context).pop();
                    widget.onOpenSettings();
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        DsIcons.svg(
                          DsIcons.settings,
                          size: 18,
                          color: ds.labelPrimary,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          s.settings,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: ds.labelPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSessionRow({
    required BuildContext context,
    required SessionSummary item,
    required bool isActive,
    required String fallbackTitle,
    required DsColors ds,
    required String renameLabel,
    required String deleteLabel,
  }) {
    if (_renamingId == item.id) {
      return Container(
        height: 44,
        margin: const EdgeInsets.symmetric(vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: ds.bgBase,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: ds.brandPrimary, width: 1.2),
        ),
        alignment: Alignment.center,
        child: TextField(
          controller: _renameController,
          focusNode: _renameFocus,
          style: TextStyle(fontSize: 15, color: ds.labelPrimary),
          decoration: const InputDecoration(
            isDense: true,
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _commitRename(item.id),
          onTapOutside: (_) => _commitRename(item.id),
        ),
      );
    }

    final displayTitle =
        item.title.trim().isEmpty ? fallbackTitle : item.title;

    return Container(
      height: 44,
      margin: const EdgeInsets.symmetric(vertical: 1),
      decoration: BoxDecoration(
        color: isActive ? ds.sidebarItemActiveBg : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: InkWell(
        onTap: () {
          context.read<ChatProvider>().openSession(item.id);
          Navigator.of(context).pop();
        },
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 4, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: isActive ? FontWeight.w500 : FontWeight.w400,
                    color:
                        isActive ? ds.brandPrimaryInvert : ds.labelPrimary,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                icon: DsIcons.svg(
                  DsIcons.ellipsis,
                  size: 16,
                  color: isActive
                      ? ds.brandPrimaryInvert.withValues(alpha: 0.8)
                      : ds.labelTertiary,
                ),
                color: ds.bgLayer3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: ds.isDark
                      ? BorderSide(color: Colors.white.withValues(alpha: 0.08))
                      : BorderSide.none,
                ),
                onSelected: (value) {
                  if (value == 'rename') {
                    _startRename(item, fallbackTitle);
                  } else if (value == 'delete') {
                    _confirmDelete(item);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'rename',
                    child: Row(
                      children: [
                        DsIcons.svg(DsIcons.edit,
                            size: 15, color: ds.labelPrimary),
                        const SizedBox(width: 8),
                        Text(renameLabel,
                            style: TextStyle(
                                fontSize: 14, color: ds.labelPrimary)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        DsIcons.svg(DsIcons.trash,
                            size: 15, color: ds.errorPrimary),
                        const SizedBox(width: 8),
                        Text(deleteLabel,
                            style: TextStyle(
                                fontSize: 14, color: ds.errorPrimary)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
