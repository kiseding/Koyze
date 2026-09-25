import 'dart:async';
import 'package:koyze/l10n/app_strings.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../../../core/io/bounded_input.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/auto_text_input.dart';
import '../domain/custom_source.dart';
import '../domain/custom_source_service.dart';
import '../domain/source_script_validation.dart';
import 'custom_source_provider.dart';
import '../../../core/widgets/fx_icon_button.dart';
import '../../../core/widgets/fx_switch.dart';

class CustomSourceScreen extends ConsumerStatefulWidget {
  const CustomSourceScreen({super.key});

  @override
  ConsumerState<CustomSourceScreen> createState() => _CustomSourceScreenState();
}

class _CustomSourceScreenState extends ConsumerState<CustomSourceScreen> {
  final Set<String> _initializingSources = {};

  @override
  Widget build(BuildContext context) {
    final sources = ref.watch(customSourcesProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: FxIconButton(
          tooltip: S.of(context).back,
          icon: Icon(Icons.arrow_back, color: AppColors.onScaffold(context)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          S.of(context).customSourcesTitle,
          style: TextStyle(
            color: AppColors.onScaffold(context),
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          FxIconButton(
            icon: Icon(Icons.file_open, color: AppColors.onScaffold(context)),
            tooltip: S.of(context).importLocalScript,
            onPressed: () => _pickAndImportFile(context, ref),
          ),
          FxIconButton(
            icon: Icon(
              Icons.cloud_download,
              color: AppColors.onScaffold(context),
            ),
            tooltip: S.of(context).importFromLink,
            onPressed: () => _showUrlImportDialog(context, ref),
          ),
          FxIconButton(
            icon: Icon(Icons.add, color: AppColors.onScaffold(context)),
            tooltip: S.of(context).addManually,
            onPressed: () => _showAddDialog(context, ref),
          ),
          FxIconButton(
            icon: Icon(Icons.link, color: AppColors.onScaffold(context)),
            tooltip: S.of(context).pasteScript,
            onPressed: () => _showImportDialog(context, ref),
          ),
        ],
      ),
      body: sources.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.code,
                    size: 64,
                    color: AppColors.mutedText(context),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    S.of(context).noCustomSources,
                    style: TextStyle(
                      color: AppColors.mutedText(context),
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    S.of(context).addCustomSourceHint,
                    style: TextStyle(
                      color: AppColors.mutedText(context),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: sources.length,
              itemBuilder: (context, index) {
                final source = sources[index];
                return _buildSourceItem(context, ref, source);
              },
            ),
    );
  }

  Widget _buildSourceItem(
    BuildContext context,
    WidgetRef ref,
    CustomSource source,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.name,
                      style: TextStyle(
                        color: AppColors.onScaffold(context),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'v${source.version} · ${source.author}',
                      style: TextStyle(
                        color: AppColors.mutedText(context),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (_initializingSources.contains(source.id))
                const SizedBox(
                  width: 59,
                  height: 32,
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else
                FxSwitch(
                  value: source.isEnabled,
                  activeColor: AppColors.accentOf(context),
                  inactiveTrackColor: AppColors.isDark(context)
                      ? AppColors.surfaceVariant
                      : AppColors.lightSurfaceVariant,
                  onChanged: (value) async {
                    final messenger = ScaffoldMessenger.of(context);
                    setState(() => _initializingSources.add(source.id));
                    bool ok = true;
                    try {
                      ok = await ref
                          .read(customSourcesProvider.notifier)
                          .toggleSource(source.id);
                    } catch (_) {
                      ok = false;
                    } finally {
                      if (mounted) {
                        setState(() => _initializingSources.remove(source.id));
                      }
                    }
                    if (!ok && mounted) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(S.of(context).sourceInitFailed(source.name)),
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    }
                  },
                ),
            ],
          ),
          if (source.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              source.description,
              style: TextStyle(
                color: AppColors.secondaryText(context),
                fontSize: 14,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.terminal, size: 16),
                label: Text(S.of(context).log),
                onPressed: () => _showLogDialog(context, ref, source),
              ),
              TextButton.icon(
                icon: const Icon(Icons.edit, size: 16),
                label: Text(S.of(context).edit),
                onPressed: () => _showEditDialog(context, ref, source),
              ),
              TextButton.icon(
                icon: const Icon(Icons.share, size: 16),
                label: Text(S.of(context).export),
                onPressed: () => _showExportDialog(context, ref, source),
              ),
              TextButton.icon(
                icon: const Icon(Icons.delete, size: 16, color: Colors.red),
                label: Text(S.of(context).delete, style: TextStyle(color: Colors.red)),
                onPressed: () => _showDeleteDialog(context, ref, source),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndImportFile(BuildContext context, WidgetRef ref) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['js'],
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final bytes = await readFileBytesBounded(
          file,
          maximumBytes: CustomSourceService.maximumScriptBytes,
        );
        final content = utf8.decode(bytes);

        final success = await ref
            .read(customSourcesProvider.notifier)
            .importLxMusicScript(content);

        if (context.mounted) {
          showAppNotification(
            success ? S.of(context).importScriptOk : S.of(context).importScriptBad,
            type: success
                ? AppNotificationType.success
                : AppNotificationType.error,
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        showAppNotification(S.of(context).readFileFailed(e), type: AppNotificationType.error);
      }
    }
  }

  void _showAddDialog(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    final authorController = TextEditingController();
    final scriptController = TextEditingController();
    final nameFocus = FocusNode();
    var keyboardRequested = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        if (!keyboardRequested) {
          keyboardRequested = true;
          requestTextInput(dialogContext, nameFocus);
        }
        return AlertDialog(
          backgroundColor: AppColors.dialogBg(dialogContext),
          title: Text(
            S.of(context).addCustomSource,
            style: TextStyle(color: AppColors.onScaffold(dialogContext)),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildTextField(
                  dialogContext,
                  nameController,
                  S.of(context).sourceName,
                  focusNode: nameFocus,
                  autofocus: true,
                ),
                const SizedBox(height: 8),
                _buildTextField(dialogContext, descController, S.of(context).descriptionLabel),
                const SizedBox(height: 8),
                _buildTextField(dialogContext, authorController, S.of(context).author),
                const SizedBox(height: 8),
                _buildTextField(
                  dialogContext,
                  scriptController,
                  S.of(context).script,
                  maxLines: 10,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                S.of(context).cancel,
                style: TextStyle(color: AppColors.mutedText(dialogContext)),
              ),
            ),
            TextButton(
              onPressed: () {
                if (nameController.text.isNotEmpty &&
                    scriptController.text.isNotEmpty) {
                  final source = CustomSource(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    name: nameController.text,
                    description: descController.text,
                    version: '1.0.0',
                    author: authorController.text,
                    script: scriptController.text,
                    createdAt: DateTime.now(),
                    updatedAt: DateTime.now(),
                  );
                  ref.read(customSourcesProvider.notifier).addSource(source);
                  Navigator.pop(dialogContext);
                }
              },
              child: Text(
                S.of(context).add,
                style: TextStyle(color: AppColors.accentOf(dialogContext)),
              ),
            ),
          ],
        );
      },
    ).whenComplete(() {
      nameController.dispose();
      descController.dispose();
      authorController.dispose();
      scriptController.dispose();
      nameFocus.dispose();
    });
  }

  void _showEditDialog(
    BuildContext context,
    WidgetRef ref,
    CustomSource source,
  ) {
    final nameController = TextEditingController(text: source.name);
    final descController = TextEditingController(text: source.description);
    final authorController = TextEditingController(text: source.author);
    final scriptController = TextEditingController(text: source.script);
    final nameFocus = FocusNode();
    var keyboardRequested = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        if (!keyboardRequested) {
          keyboardRequested = true;
          requestTextInput(dialogContext, nameFocus);
        }
        return AlertDialog(
          backgroundColor: AppColors.dialogBg(dialogContext),
          title: Text(
            S.of(context).editCustomSource,
            style: TextStyle(color: AppColors.onScaffold(dialogContext)),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildTextField(
                  dialogContext,
                  nameController,
                  S.of(context).sourceName,
                  focusNode: nameFocus,
                  autofocus: true,
                ),
                const SizedBox(height: 8),
                _buildTextField(dialogContext, descController, S.of(context).descriptionLabel),
                const SizedBox(height: 8),
                _buildTextField(dialogContext, authorController, S.of(context).author),
                const SizedBox(height: 8),
                _buildTextField(
                  dialogContext,
                  scriptController,
                  S.of(context).script,
                  maxLines: 10,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                S.of(context).cancel,
                style: TextStyle(color: AppColors.mutedText(dialogContext)),
              ),
            ),
            TextButton(
              onPressed: () {
                final updated = source.copyWith(
                  name: nameController.text,
                  description: descController.text,
                  author: authorController.text,
                  script: scriptController.text,
                );
                ref.read(customSourcesProvider.notifier).updateSource(updated);
                Navigator.pop(dialogContext);
              },
              child: Text(
                S.of(context).save,
                style: TextStyle(color: AppColors.accentOf(dialogContext)),
              ),
            ),
          ],
        );
      },
    ).whenComplete(() {
      nameController.dispose();
      descController.dispose();
      authorController.dispose();
      scriptController.dispose();
      nameFocus.dispose();
    });
  }

  void _showUrlImportDialog(BuildContext context, WidgetRef ref) {
    final pageContext = context;
    final controller = TextEditingController();
    final inputFocus = FocusNode();
    var keyboardRequested = false;
    bool isLoading = false;

    showDialog(
      context: pageContext,
      barrierDismissible: true,
      builder: (dialogContext) {
        if (!keyboardRequested) {
          keyboardRequested = true;
          requestTextInput(dialogContext, inputFocus);
        }
        return StatefulBuilder(
          builder: (dialogContext, setState) {
            Future<void> importUrl(String url) async {
              if (url.isEmpty || !url.startsWith('https://')) {
                showAppNotification(
                  S.of(context).httpsLinkRequired,
                  type: AppNotificationType.error,
                );
                return;
              }

              setState(() => isLoading = true);
              final success = await ref.read(importCustomSourceFromUrlProvider)(
                url,
              );
              if (!dialogContext.mounted || !pageContext.mounted) return;
              setState(() => isLoading = false);
              Navigator.pop(dialogContext);
              showAppNotification(
                success ? S.of(context).importOk : S.of(context).importLinkBad,
                type: success
                    ? AppNotificationType.success
                    : AppNotificationType.error,
              );
            }

            return AlertDialog(
              backgroundColor: AppColors.dialogBg(dialogContext),
              title: Text(
                S.of(context).importFromLink,
                style: TextStyle(color: AppColors.onScaffold(dialogContext)),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    S.of(context).directDownloadHint,
                    style: TextStyle(
                      color: AppColors.mutedText(dialogContext),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    focusNode: inputFocus,
                    autofocus: true,
                    keyboardType: desktopSafeKeyboardType(TextInputType.url),
                    textInputAction: TextInputAction.done,
                    autocorrect: false,
                    style: TextStyle(
                      color: AppColors.onScaffold(dialogContext),
                    ),
                    decoration: InputDecoration(
                      hintText: 'https://...',
                      hintStyle: TextStyle(
                        color: AppColors.mutedText(dialogContext),
                      ),
                      filled: true,
                      fillColor: AppColors.fill2(dialogContext),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                  ),
                  if (isLoading) ...[
                    const SizedBox(height: 16),
                    Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.accentOf(dialogContext),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isLoading
                      ? null
                      : () => Navigator.pop(dialogContext),
                  child: Text(
                    S.of(context).cancel,
                    style: TextStyle(color: AppColors.mutedText(dialogContext)),
                  ),
                ),
                TextButton(
                  onPressed: isLoading
                      ? null
                      : () async {
                          final content = await Clipboard.getData(
                            Clipboard.kTextPlain,
                          );
                          if (!dialogContext.mounted) return;
                          final url = content?.text?.trim() ?? '';
                          if (url.isEmpty) {
                            showAppNotification(
                              S.of(context).clipboardEmpty,
                              type: AppNotificationType.error,
                            );
                            return;
                          }
                          controller.text = url;
                          await importUrl(url);
                        },
                  child: Text(
                    S.of(context).clipboard,
                    style: TextStyle(color: AppColors.accentOf(dialogContext)),
                  ),
                ),
                TextButton(
                  onPressed: isLoading
                      ? null
                      : () => importUrl(controller.text.trim()),
                  child: Text(
                    S.of(context).importAction,
                    style: TextStyle(color: AppColors.accentOf(dialogContext)),
                  ),
                ),
              ],
            );
          },
        );
      },
    ).whenComplete(() {
      controller.dispose();
      inputFocus.dispose();
    });
  }

  void _showImportDialog(BuildContext context, WidgetRef ref) {
    final pageContext = context;
    final controller = TextEditingController();
    final inputFocus = FocusNode();
    var keyboardRequested = false;
    bool isLoading = false;

    showDialog(
      context: pageContext,
      barrierDismissible: true,
      builder: (dialogContext) {
        if (!keyboardRequested) {
          keyboardRequested = true;
          requestTextInput(dialogContext, inputFocus);
        }
        return StatefulBuilder(
          builder: (dialogContext, setState) => AlertDialog(
            backgroundColor: AppColors.dialogBg(dialogContext),
            title: Text(
              S.of(context).importCustomSource,
              style: TextStyle(color: AppColors.onScaffold(dialogContext)),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  S.of(context).lxScriptHint,
                  style: TextStyle(
                    color: AppColors.mutedText(dialogContext),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  focusNode: inputFocus,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  autocorrect: false,
                  style: TextStyle(
                    color: AppColors.onScaffold(dialogContext),
                    fontFamily: 'monospace',
                  ),
                  maxLines: 10,
                  decoration: InputDecoration(
                    hintText: S.of(context).pasteScriptHint,
                    hintStyle: TextStyle(
                      color: AppColors.mutedText(dialogContext),
                    ),
                    filled: true,
                    fillColor: AppColors.fill2(dialogContext),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                if (isLoading) ...[
                  const SizedBox(height: 16),
                  Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.accentOf(dialogContext),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: isLoading
                    ? null
                    : () => Navigator.pop(dialogContext),
                child: Text(
                  S.of(context).cancel,
                  style: TextStyle(color: AppColors.mutedText(dialogContext)),
                ),
              ),
              TextButton(
                onPressed: isLoading
                    ? null
                    : () async {
                        final text = controller.text.trim();
                        setState(() => isLoading = true);
                        bool success = false;

                        if (isValidSourceScript(text)) {
                          success = await ref
                              .read(customSourcesProvider.notifier)
                              .importLxMusicScript(text);
                        } else {
                          success = await ref
                              .read(customSourcesProvider.notifier)
                              .importSource(text);
                        }

                        if (!dialogContext.mounted || !pageContext.mounted) {
                          return;
                        }
                        setState(() => isLoading = false);
                        Navigator.pop(dialogContext);
                        showAppNotification(
                          success ? S.of(context).importOk : S.of(context).importFormatBad,
                          type: success
                              ? AppNotificationType.success
                              : AppNotificationType.error,
                        );
                      },
                child: Text(
                  S.of(context).importAction,
                  style: TextStyle(color: AppColors.accentOf(dialogContext)),
                ),
              ),
            ],
          ),
        );
      },
    ).whenComplete(() {
      controller.dispose();
      inputFocus.dispose();
    });
  }

  void _showExportDialog(
    BuildContext context,
    WidgetRef ref,
    CustomSource source,
  ) {
    final jsonStr = const JsonEncoder.withIndent('  ').convert(source.toJson());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.dialogBg(context),
        title: Text(
          S.of(context).exportCustomSource,
          style: TextStyle(color: AppColors.onScaffold(context)),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Text(
              jsonStr,
              style: TextStyle(
                color: AppColors.onScaffold(context),
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              S.of(context).close,
              style: TextStyle(color: AppColors.mutedText(context)),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(
    BuildContext context,
    WidgetRef ref,
    CustomSource source,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.dialogBg(context),
        title: Text(
          S.of(context).deleteCustomSource,
          style: TextStyle(color: AppColors.onScaffold(context)),
        ),
        content: Text(
          S.of(context).deleteSourceConfirm(source.name),
          style: TextStyle(color: AppColors.secondaryText(context)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              S.of(context).cancel,
              style: TextStyle(color: AppColors.mutedText(context)),
            ),
          ),
          TextButton(
            onPressed: () {
              ref.read(customSourcesProvider.notifier).deleteSource(source.id);
              Navigator.pop(context);
            },
            child: Text(S.of(context).delete, style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showLogDialog(
    BuildContext context,
    WidgetRef ref,
    CustomSource source,
  ) {
    showDialog(
      context: context,
      builder: (context) => _LogConsole(source: source),
    );
  }

  Widget _buildTextField(
    BuildContext context,
    TextEditingController controller,
    String label, {
    int maxLines = 1,
    FocusNode? focusNode,
    bool autofocus = false,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      style: TextStyle(color: AppColors.onScaffold(context)),
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: AppColors.mutedText(context)),
        filled: true,
        fillColor: AppColors.fill2(context),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _LogConsole extends ConsumerStatefulWidget {
  final CustomSource source;
  const _LogConsole({required this.source});

  @override
  ConsumerState<_LogConsole> createState() => _LogConsoleState();
}

class _LogConsoleState extends ConsumerState<_LogConsole> {
  final List<Map<String, dynamic>> _logs = [];
  final ScrollController _scrollController = ScrollController();
  StreamSubscription<Map<String, dynamic>>? _logSubscription;

  @override
  void initState() {
    super.initState();
    _listenLogs();
  }

  Future<void> _copyLogs() async {
    final buffer = StringBuffer();
    for (final log in _logs) {
      final message = log['message'] ?? log['event'] ?? '';
      buffer
        ..write('[${_formatTime(log['timestamp'])}] ')
        ..writeln(message);
      final data = log['data'];
      if (data != null) {
        buffer.writeln('  ${json.encode(data)}');
      }
    }
    if (buffer.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!mounted) return;
    showAppNotification(S.of(context).logCopied, type: AppNotificationType.success);
  }

  void _listenLogs() {
    _logSubscription = ref
        .read(customSourceEventStreamProvider(widget.source.id))
        .listen((event) {
          if (!mounted) return;
          setState(() {
            _logs.add({...event, 'timestamp': DateTime.now()});
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_scrollController.hasClients) return;
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          });
        });
  }

  @override
  void dispose() {
    _logSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.dialogBg(context),
      title: Row(
        children: [
          Icon(Icons.terminal, color: AppColors.onScaffold(context), size: 20),
          const SizedBox(width: 8),
          Text(
            S.of(context).sourceLogTitle(widget.source.name),
            style: TextStyle(
              color: AppColors.onScaffold(context),
              fontSize: 16,
            ),
          ),
          const Spacer(),
          FxIconButton(
            icon: Icon(
              Icons.delete_sweep,
              color: AppColors.mutedText(context),
              size: 20,
            ),
            onPressed: () => setState(() => _logs.clear()),
          ),
        ],
      ),
      content: Container(
        width: double.maxFinite,
        height: 400,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.fill(context),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.cardBorder(context)),
        ),
        child: _logs.isEmpty
            ? Center(
                child: Text(
                  S.of(context).noLog,
                  style: TextStyle(color: AppColors.mutedText(context)),
                ),
              )
            : ListView.builder(
                controller: _scrollController,
                itemCount: _logs.length,
                itemBuilder: (context, index) {
                  final log = _logs[index];
                  final type = log['type'];
                  Color color = AppColors.secondaryText(context);
                  if (type == 'error') color = AppColors.error;
                  if (type == 'event') color = AppColors.accentOf(context);

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                        children: [
                          TextSpan(
                            text: '[${_formatTime(log['timestamp'])}] ',
                            style: TextStyle(
                              color: AppColors.mutedText(context),
                            ),
                          ),
                          TextSpan(
                            text: '${log['message'] ?? log['event'] ?? ''}\n',
                            style: TextStyle(color: color),
                          ),
                          if (log['data'] != null)
                            TextSpan(
                              text: '  ${json.encode(log['data'])}\n',
                              style: TextStyle(
                                color: AppColors.mutedText(context),
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
      actions: [
        Row(
          children: [
            TextButton.icon(
              onPressed: _logs.isEmpty ? null : _copyLogs,
              icon: const Icon(Icons.copy, size: 16),
              label: Text(S.of(context).copyLog),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.accentOf(context),
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                S.of(context).close,
                style: TextStyle(color: AppColors.mutedText(context)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }
}
