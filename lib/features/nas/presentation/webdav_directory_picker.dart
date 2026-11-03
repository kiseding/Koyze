import 'package:flutter/material.dart';
import 'package:koyze/l10n/app_strings.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/loading_widget.dart';
import '../domain/webdav_client.dart';

/// 挑 WebDAV 目录。返回的路径相对服务地址（`/` 表示服务根）。
Future<String?> showWebDavDirectoryPicker(
  BuildContext context, {
  required Future<List<WebDavDirectory>> Function(String path) load,
  VoidCallback? onDispose,
  String initialPath = '/',
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _WebDavDirectoryPicker(
      load: load,
      onDispose: onDispose,
      initialPath: initialPath,
    ),
  );
}

class _WebDavDirectoryPicker extends StatefulWidget {
  const _WebDavDirectoryPicker({
    required this.load,
    required this.initialPath,
    this.onDispose,
  });

  final Future<List<WebDavDirectory>> Function(String path) load;
  final VoidCallback? onDispose;
  final String initialPath;

  @override
  State<_WebDavDirectoryPicker> createState() => _WebDavDirectoryPickerState();
}

class _WebDavDirectoryPickerState extends State<_WebDavDirectoryPicker> {
  late String _path = _normalize(widget.initialPath);
  List<WebDavDirectory> _directories = const [];
  bool _loading = true;
  String? _error;

  static String _normalize(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == '/') return '/';
    final stripped = trimmed.replaceFirst(RegExp(r'^/+'), '');
    return '/${stripped.replaceAll(RegExp(r'/+$'), '')}';
  }

  @override
  void initState() {
    super.initState();
    _load(_path);
  }

  @override
  void dispose() {
    widget.onDispose?.call();
    super.dispose();
  }

  Future<void> _load(String path) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final directories = await widget.load(path);
      if (!mounted) return;
      setState(() {
        _path = path;
        _directories = directories;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  String get _parent {
    if (_path == '/') return '/';
    final parts = _path.split('/').where((part) => part.isNotEmpty).toList();
    if (parts.length <= 1) return '/';
    return '/${parts.take(parts.length - 1).join('/')}';
  }

  @override
  Widget build(BuildContext context) {
    final on = AppColors.onScaffold(context);
    final muted = AppColors.mutedText(context);
    final accent = AppColors.accentOf(context);

    return SafeArea(
      top: false,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.72,
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.fromBorderSide(
            AppGlass.hairline(context, emphasized: false),
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: muted.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: S.of(context).back,
                    icon: Icon(Icons.arrow_back, color: on),
                    onPressed: _path == '/'
                        ? null
                        : () => _load(_parent),
                  ),
                  Expanded(
                    child: Text(
                      _path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: on,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: AppLoadingIndicator())
                  : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: muted, fontSize: 13),
                        ),
                      ),
                    )
                  : _directories.isEmpty
                  ? Center(
                      child: Text(
                        S.of(context).noData,
                        style: TextStyle(color: muted, fontSize: 13),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: _directories.length,
                      itemBuilder: (context, index) {
                        final dir = _directories[index];
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            Icons.folder_outlined,
                            color: accent,
                            size: 22,
                          ),
                          title: Text(
                            dir.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: on, fontSize: 14),
                          ),
                          onTap: () => _load(_normalize(dir.path)),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _loading
                      ? null
                      : () => Navigator.of(context).pop(_path),
                  child: Text(S.of(context).useThisFolder),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
