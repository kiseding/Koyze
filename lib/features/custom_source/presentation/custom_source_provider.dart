import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/buildless_notifier.dart';
import '../domain/custom_source.dart';
import '../domain/custom_source_service.dart';

final customSourceServiceProvider = Provider<CustomSourceService>((ref) {
  final service = CustomSourceService();
  // 在应用启动时初始化一次
  service.init();
  ref.onDispose(service.dispose);
  return service;
});

final customSourceRevisionProvider = StreamProvider<int>((ref) {
  return ref.watch(customSourceServiceProvider).revisionStream;
});

final customSourcesProvider =
    NotifierProvider<CustomSourcesNotifier, List<CustomSource>>(
      CustomSourcesNotifier.new,
    );

class CustomSourcesNotifier extends BuildlessNotifier<List<CustomSource>> {
  CustomSourcesNotifier({CustomSourceService? service})
    : _serviceOverride = service,
      super(const []);

  final CustomSourceService? _serviceOverride;

  /// Resolved either from the constructor (tests) or from [build] (Riverpod).
  late CustomSourceService _service;
  int _generation = 0;

  @override
  List<CustomSource> build() {
    _service = _serviceOverride ?? ref.watch(customSourceServiceProvider);
    _loadSources();
    return super.build();
  }

  Future<void> _loadSources() async {
    final generation = ++_generation;
    await _service.init();
    if (generation != _generation) return;
    publish(_service.sources);
  }

  Future<void> addSource(CustomSource source) async {
    final generation = ++_generation;
    await _service.addSource(source);
    if (generation != _generation) return;
    publish(_service.sources);
  }

  Future<void> updateSource(CustomSource source) async {
    final generation = ++_generation;
    await _service.updateSource(source);
    if (generation != _generation) return;
    publish(_service.sources);
  }

  Future<void> deleteSource(String id) async {
    final generation = ++_generation;
    await _service.deleteSource(id);
    if (generation != _generation) return;
    publish(_service.sources);
  }

  Future<bool> toggleSource(String id) async {
    final generation = ++_generation;
    final result = await _service.toggleSource(id);
    if (generation != _generation) return false;
    publish(_service.sources);
    return result;
  }

  Future<bool> importSource(String jsonStr) async {
    final generation = ++_generation;
    final result = await _service.importSource(jsonStr);
    if (generation == _generation) publish(_service.sources);
    return result;
  }

  Future<bool> importLxMusicScript(String script) async {
    final result = await importLxMusicScriptWithResult(script);
    return result.success;
  }

  Future<CustomSourceImportResult> importLxMusicScriptWithResult(
    String script,
  ) async {
    final generation = ++_generation;
    final result = await _service.importLxMusicScriptWithResult(script);
    if (generation == _generation) publish(_service.sources);
    return result;
  }

  Future<bool> importSourceFromUrl(String url) async {
    final generation = ++_generation;
    final result = await _service.importSourceFromUrl(url);
    if (generation == _generation) publish(_service.sources);
    return result;
  }

  Future<void> replaceAllSources(List<CustomSource> sources) async {
    final generation = ++_generation;
    await _service.replaceAllSources(sources);
    if (generation == _generation) publish(_service.sources);
  }

  String exportSource(String id) {
    return _service.exportSource(id);
  }

  String exportAllSources() {
    return _service.exportAllSources();
  }

  Stream<Map<String, dynamic>> getEventStream(String sourceId) {
    return _service.getEventStream(sourceId);
  }
}

final importCustomSourceFromUrlProvider =
    Provider<Future<bool> Function(String)>((ref) {
      return ref.read(customSourcesProvider.notifier).importSourceFromUrl;
    });

final customSourceEventStreamProvider =
    Provider.family<Stream<Map<String, dynamic>>, String>((ref, sourceId) {
      return ref.read(customSourcesProvider.notifier).getEventStream(sourceId);
    });
