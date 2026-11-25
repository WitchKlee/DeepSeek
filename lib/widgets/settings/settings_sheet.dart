import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/location_data.dart';
import '../../models/settings_models.dart';
import '../../providers/chat_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/api/api_errors.dart';
import '../../services/storage/history_backup.dart';
import '../../theme/ds_icons.dart';
import '../../theme/ds_theme.dart';
import '../common/ds_modals.dart';
import '../common/ds_toast.dart';

enum SettingsTab { general, data }

/// Opens the DeepSeek mobile Settings bottom sheet (`24px` top radius).
Future<void> showDsSettingsSheet(
  BuildContext context, {
  SettingsTab initialTab = SettingsTab.general,
}) {
  final ds = context.ds;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: ds.bgLayer2,
    barrierColor: Colors.black.withValues(alpha: ds.isDark ? 0.60 : 0.36),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _SettingsSheetContent(initialTab: initialTab),
  );
}

class _SettingsSheetContent extends StatefulWidget {
  final SettingsTab initialTab;
  const _SettingsSheetContent({required this.initialTab});

  @override
  State<_SettingsSheetContent> createState() => _SettingsSheetContentState();
}

class _SettingsSheetContentState extends State<_SettingsSheetContent> {
  late SettingsTab _tab;

  // API Key form
  bool _editingApiKey = false;
  bool _verifyingKey = false;
  String? _apiKeyError;
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _apiOriginController = TextEditingController();

  // Backup progress
  bool _importing = false;
  bool _exporting = false;
  bool _deletingAll = false;
  int _progressDone = 0;
  int _progressTotal = 0;
  String? _importStatusText;
  bool _importStatusError = false;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
    final settings = context.read<SettingsProvider>().settings;
    _editingApiKey = settings.apiKey == null || settings.apiKey!.isEmpty;
    _apiOriginController.text = settings.apiOrigin;
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _apiOriginController.dispose();
    super.dispose();
  }

  Future<void> _submitApiKey() async {
    final key = _apiKeyController.text.trim();
    if (key.isEmpty || _verifyingKey) return;
    final settingsProv = context.read<SettingsProvider>();
    final s = settingsProv.strings;

    setState(() {
      _verifyingKey = true;
      _apiKeyError = null;
    });

    try {
      await settingsProv.verifyAndSaveApiKey(key);
      if (!mounted) return;
      _apiKeyController.clear();
      setState(() {
        _verifyingKey = false;
        _editingApiKey = false;
      });
      DsToast.show(context, s.apiKeySaved);
    } catch (e) {
      if (!mounted) return;
      String errText;
      if (e is ApiError) {
        final cond = classifyApiError(e);
        if (cond == ApiErrorCondition.unauthorized) {
          errText = s.apiKeyInvalid;
        } else if (cond == ApiErrorCondition.network) {
          errText = s.networkError;
        } else {
          errText = s.verifyFailed(e.message);
        }
      } else {
        errText = s.verifyFailed(e.toString());
      }
      setState(() {
        _verifyingKey = false;
        _apiKeyError = errText;
      });
    }
  }

  Future<void> _handleImportZip() async {
    final s = context.read<SettingsProvider>().strings;
    final chat = context.read<ChatProvider>();

    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (picked.isEmpty || !mounted) return;

    final file = picked.first;
    final bytes = await file.readAsBytes();
    if (!mounted) return;

    final ok = await showDsConfirmDialog(
      context: context,
      title: s.importConfirmTitle,
      body: s.importConfirmDesc,
      cancelText: s.cancel,
      confirmText: s.importAction,
      dangerOutlined: true,
    );
    if (!ok || !mounted) return;

    setState(() {
      _importing = true;
      _progressDone = 0;
      _progressTotal = 0;
      _importStatusText = null;
      _importStatusError = false;
    });

    try {
      final count = await chat.importHistoryZip(
        bytes,
        onProgress: (done, total) {
          if (mounted) {
            setState(() {
              _progressDone = done;
              _progressTotal = total;
            });
          }
        },
      );
      if (!mounted) return;
      setState(() {
        _importing = false;
        _importStatusText = s.importedChats(count);
        _importStatusError = false;
      });
      DsToast.show(context, s.importedChats(count));
    } catch (e) {
      if (!mounted) return;
      final msg =
          e is BackupException ? e.localize(s) : s.backupIncomplete;
      setState(() {
        _importing = false;
        _importStatusText = msg;
        _importStatusError = true;
      });
      DsToast.show(context, msg, isError: true);
    }
  }

  Future<void> _handleExportZip() async {
    final s = context.read<SettingsProvider>().strings;
    final chat = context.read<ChatProvider>();
    if (chat.summaries.isEmpty) return;

    setState(() => _exporting = true);
    try {
      final tempDir = await getTemporaryDirectory();
      final zipFile = await chat.exportHistoryZip(outputDir: tempDir);
      if (!mounted) return;
      setState(() => _exporting = false);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(zipFile.path)],
          subject: zipFile.uri.pathSegments.last,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _exporting = false);
      DsToast.show(context, s.backupIncomplete, isError: true);
    }
  }

  Future<void> _handleDeleteAll() async {
    final s = context.read<SettingsProvider>().strings;
    final chat = context.read<ChatProvider>();

    final ok = await showDsConfirmDialog(
      context: context,
      title: s.deleteAllConfirmTitle,
      body: s.deleteAllConfirmDesc,
      cancelText: s.cancel,
      confirmText: s.deleteAllChats,
      danger: true,
    );
    if (!ok || !mounted) return;

    setState(() => _deletingAll = true);
    await chat.deleteAllSessions();
    if (!mounted) return;
    setState(() => _deletingAll = false);
    DsToast.show(context, s.deleteSuccess);
  }

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final settingsProv = context.watch<SettingsProvider>();
    final settings = settingsProv.settings;
    final s = settingsProv.strings;
    final chat = context.watch<ChatProvider>();
    final sheetH = (MediaQuery.of(context).size.height - 64).clamp(420.0, 760.0);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        height: sheetH,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                child: Row(
                  children: [
                    Text(
                      s.settings,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: ds.labelPrimary,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: DsIcons.svg(
                        DsIcons.close,
                        size: 16,
                        color: ds.labelSecondary,
                      ),
                    ),
                  ],
                ),
              ),

              // Horizontal tabs matching chat-demo mobile sheet
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _TabButton(
                      iconSvg: DsIcons.settings,
                      label: s.generalSettings,
                      active: _tab == SettingsTab.general,
                      onTap: () => setState(() => _tab = SettingsTab.general),
                    ),
                    const SizedBox(width: 8),
                    _TabButton(
                      iconSvg: DsIcons.data,
                      label: s.dataManagement,
                      active: _tab == SettingsTab.data,
                      onTap: () => setState(() => _tab = SettingsTab.data),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Divider(height: 1, color: ds.borderL2Thin),

              // Tab body
              Expanded(
                child: _tab == SettingsTab.general
                    ? _buildGeneralTab(settingsProv, settings, ds)
                    : _buildDataTab(settingsProv, settings, chat, ds),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGeneralTab(
    SettingsProvider prov,
    AppSettings settings,
    DsColors ds,
  ) {
    final s = prov.strings;
    final isZh = settings.locale.startsWith('zh');
    final curProvince = settings.location?.province;
    final cities = curProvince != null
        ? getCitiesForProvince(curProvince)
        : <MapEntry<String, String>>[];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      children: [
        // 1. Theme cards
        Text(
          s.theme,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: ds.labelPrimary,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _ThemeCard(
                iconSvg: DsIcons.lightTheme,
                label: s.themeLight,
                selected: settings.themePreference == ThemePreference.light,
                onTap: () => prov.setThemePreference(ThemePreference.light),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ThemeCard(
                iconSvg: DsIcons.darkTheme,
                label: s.themeDark,
                selected: settings.themePreference == ThemePreference.dark,
                onTap: () => prov.setThemePreference(ThemePreference.dark),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ThemeCard(
                iconSvg: DsIcons.systemTheme,
                label: s.themeSystem,
                selected: settings.themePreference == ThemePreference.system,
                onTap: () => prov.setThemePreference(ThemePreference.system),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // 2. Language
        _SettingRow(
          label: s.language,
          trailing: _PillDropdown<String>(
            value: settings.locale,
            items: const [
              DropdownMenuItem(value: 'zh-CN', child: Text('简体中文')),
              DropdownMenuItem(value: 'en-US', child: Text('English')),
            ],
            onChanged: (v) {
              if (v != null) prov.setLocale(v);
            },
          ),
        ),
        Divider(height: 24, color: ds.borderL2Thin),

        // 3. Read-aloud voice
        _SettingRow(
          label: s.readAloudVoice,
          trailing: _PillDropdown<TtsVoice>(
            value: settings.ttsVoice,
            items: [
              DropdownMenuItem(
                value: TtsVoice.stella,
                child: Text(s.voiceStella),
              ),
              DropdownMenuItem(
                value: TtsVoice.tide,
                child: Text(s.voiceTide),
              ),
            ],
            onChanged: (v) {
              if (v != null) prov.setTtsVoice(v);
            },
          ),
        ),
        Divider(height: 24, color: ds.borderL2Thin),

        // 4. Model selector
        _SettingRow(
          label: s.modelLabel,
          trailing: _PillDropdown<String>(
            value: AppSettings.availableModels.contains(settings.model)
                ? settings.model
                : AppSettings.defaultModel,
            items: AppSettings.availableModels
                .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                .toList(),
            onChanged: (v) {
              if (v != null) prov.setModel(v);
            },
          ),
        ),
        Divider(height: 24, color: ds.borderL2Thin),

        // 5. Location
        Text(
          s.location,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: ds.labelPrimary,
          ),
        ),
        const SizedBox(height: 10),
        if (isZh)
          Row(
            children: [
              Expanded(
                child: _PillDropdown<String>(
                  value: curProvince ?? '',
                  isExpanded: true,
                  items: [
                    DropdownMenuItem(value: '', child: Text(s.selectProvince)),
                    for (final entry in kProvinceNames.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                  ],
                  onChanged: (v) {
                    if (v == null || v.isEmpty) {
                      prov.setLocation(null);
                    } else {
                      prov.setLocation(UserLocation(region: 'CN', province: v));
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PillDropdown<String>(
                  value: settings.location?.city ?? '',
                  isExpanded: true,
                  enabled: curProvince != null && cities.isNotEmpty,
                  items: [
                    DropdownMenuItem(value: '', child: Text(s.selectCity)),
                    for (final entry in cities)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                  ],
                  onChanged: (v) {
                    if (curProvince == null) return;
                    if (v == null || v.isEmpty) {
                      prov.setLocation(
                        UserLocation(region: 'CN', province: curProvince),
                      );
                    } else {
                      prov.setLocation(
                        UserLocation(
                          region: 'CN',
                          province: curProvince,
                          city: v,
                        ),
                      );
                    }
                  },
                ),
              ),
            ],
          )
        else
          _PillDropdown<String>(
            value: settings.location?.region ?? '',
            isExpanded: true,
            items: [
              DropdownMenuItem(value: '', child: Text(s.selectRegion)),
              for (final code in kRegionCodes)
                DropdownMenuItem(
                  value: code,
                  child: Text(getRegionDisplayName(code, settings.locale)),
                ),
            ],
            onChanged: (v) {
              if (v == null || v.isEmpty) {
                prov.setLocation(null);
              } else {
                prov.setLocation(UserLocation(region: v));
              }
            },
          ),
      ],
    );
  }

  Widget _buildDataTab(
    SettingsProvider prov,
    AppSettings settings,
    ChatProvider chat,
    DsColors ds,
  ) {
    final s = prov.strings;
    final hasKey = prov.hasApiKey;
    final busy = _importing || _exporting || _deletingAll || chat.isHistoryOpBusy;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            children: [
              // 1. API Key section
              Text(
                s.enterApiKeyHeader,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: ds.labelPrimary,
                ),
              ),
              const SizedBox(height: 10),
              if (hasKey && !_editingApiKey)
                Container(
                  height: 48,
                  padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
                  decoration: BoxDecoration(
                    color: ds.loginInput,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: ds.borderL2Thin),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '*' * (settings.apiKey!.length.clamp(12, 32)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            letterSpacing: 1.5,
                            color: ds.labelCaption,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _editingApiKey = true;
                            _apiKeyError = null;
                          });
                        },
                        icon: DsIcons.svg(
                          DsIcons.edit,
                          size: 16,
                          color: ds.labelSecondary,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: ds.loginInput,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: _apiKeyError != null
                              ? ds.errorPrimary
                              : ds.brandPrimary,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: TextField(
                        controller: _apiKeyController,
                        obscureText: true,
                        onChanged: (_) => setState(() => _apiKeyError = null),
                        onSubmitted: (_) => _submitApiKey(),
                        style: TextStyle(fontSize: 15, color: ds.labelPrimary),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: s.enterApiKeyHint,
                          hintStyle: TextStyle(
                            fontSize: 15,
                            color: ds.labelCaption,
                          ),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    if (_apiKeyError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6, left: 6),
                        child: Text(
                          _apiKeyError!,
                          style: TextStyle(
                            fontSize: 12,
                            color: ds.errorPrimary,
                          ),
                        ),
                      ),
                  ],
                ),

              const SizedBox(height: 14),

              // Optional API Origin
              Text(
                s.apiOriginLabel,
                style: TextStyle(
                  fontSize: 13,
                  color: ds.labelTertiary,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: ds.loginInput,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: ds.borderL2Thin),
                ),
                alignment: Alignment.center,
                child: TextField(
                  controller: _apiOriginController,
                  style: TextStyle(fontSize: 13, color: ds.labelPrimary),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'https://api.deepseek.com',
                  ),
                  onSubmitted: (v) => prov.setApiOrigin(v),
                  onTapOutside: (_) =>
                      prov.setApiOrigin(_apiOriginController.text),
                ),
              ),

              Divider(height: 32, color: ds.borderL2Thin),

              // 2. Import chat history
              _DataActionRow(
                title: s.importHistory,
                description: s.importHistoryDesc,
                button: OutlinedButton(
                  onPressed: busy ? null : _handleImportZip,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ds.labelPrimary,
                    side: BorderSide(color: ds.borderL2),
                    shape: const StadiumBorder(),
                    minimumSize: const Size(76, 36),
                  ),
                  child: _importing
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: ds.brandPrimary,
                          ),
                        )
                      : Text(s.upload, style: const TextStyle(fontSize: 13)),
                ),
              ),
              if (_importing && _progressTotal > 0) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: _progressDone / _progressTotal,
                          minHeight: 4,
                          color: ds.brandPrimary,
                          backgroundColor: ds.selectorFill,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '$_progressDone / $_progressTotal',
                      style: TextStyle(
                        fontSize: 12,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: ds.labelTertiary,
                      ),
                    ),
                  ],
                ),
              ],
              if (_importStatusText != null) ...[
                const SizedBox(height: 6),
                Text(
                  _importStatusText!,
                  style: TextStyle(
                    fontSize: 12,
                    color: _importStatusError
                        ? ds.errorPrimary
                        : ds.labelSecondary,
                  ),
                ),
              ],

              Divider(height: 28, color: ds.borderL2Thin),

              // 3. Export all chats
              _DataActionRow(
                title: s.exportAllChats,
                description: s.exportAllChatsDesc,
                button: OutlinedButton(
                  onPressed: (busy || chat.summaries.isEmpty)
                      ? null
                      : _handleExportZip,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ds.labelPrimary,
                    side: BorderSide(color: ds.borderL2),
                    shape: const StadiumBorder(),
                    minimumSize: const Size(76, 36),
                  ),
                  child: _exporting
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: ds.brandPrimary,
                          ),
                        )
                      : Text(s.download, style: const TextStyle(fontSize: 13)),
                ),
              ),

              Divider(height: 28, color: ds.borderL2Thin),

              // 4. Delete all chats
              _DataActionRow(
                title: s.deleteAllChats,
                description: null,
                button: OutlinedButton(
                  onPressed: (busy || chat.summaries.isEmpty)
                      ? null
                      : _handleDeleteAll,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ds.errorPrimary,
                    side: BorderSide(
                      color: chat.summaries.isEmpty
                          ? ds.borderL2
                          : ds.errorPrimary,
                    ),
                    shape: const StadiumBorder(),
                    minimumSize: const Size(76, 36),
                  ),
                  child: Text(
                    _deletingAll ? s.deleting : s.delete,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Full-width Confirm pill button on mobile when entering API key
        if (_editingApiKey && _apiKeyController.text.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _verifyingKey ? null : _submitApiKey,
                style: FilledButton.styleFrom(
                  backgroundColor: ds.buttonPrimaryFill,
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder(),
                ),
                child: Text(
                  _verifyingKey ? s.verifying : s.confirm,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _TabButton extends StatelessWidget {
  final String iconSvg;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _TabButton({
    required this.iconSvg,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: active ? ds.interactiveHover : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DsIcons.svg(
              iconSvg,
              size: 16,
              color: active ? ds.labelPrimary : ds.labelSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: active ? ds.labelPrimary : ds.labelSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeCard extends StatelessWidget {
  final String iconSvg;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeCard({
    required this.iconSvg,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 78,
        decoration: BoxDecoration(
          color: selected ? ds.selectorFill : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? ds.brandPrimary : ds.borderL2,
            width: selected ? 1.2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            DsIcons.svg(iconSvg, size: 18, color: ds.labelPrimary),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                color: ds.labelPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  final String label;
  final Widget trailing;

  const _SettingRow({required this.label, required this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: context.ds.labelPrimary,
            ),
          ),
        ),
        trailing,
      ],
    );
  }
}

class _PillDropdown<T> extends StatelessWidget {
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final bool isExpanded;
  final bool enabled;

  const _PillDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
    this.isExpanded = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: ds.selectorFill,
        borderRadius: BorderRadius.circular(18),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: isExpanded,
          dropdownColor: ds.bgLayer3,
          borderRadius: BorderRadius.circular(14),
          style: TextStyle(fontSize: 13, color: ds.labelPrimary),
          icon: Icon(
            Icons.keyboard_arrow_down,
            size: 16,
            color: enabled ? ds.labelSecondary : ds.labelCaption,
          ),
          items: items,
          onChanged: enabled ? onChanged : null,
        ),
      ),
    );
  }
}

class _DataActionRow extends StatelessWidget {
  final String title;
  final String? description;
  final Widget button;

  const _DataActionRow({
    required this.title,
    required this.description,
    required this.button,
  });

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: ds.labelPrimary,
                ),
              ),
              if (description != null) ...[
                const SizedBox(height: 4),
                Text(
                  description!,
                  style: TextStyle(
                    fontSize: 12,
                    height: 18 / 12,
                    color: ds.labelTertiary,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 14),
        button,
      ],
    );
  }
}
