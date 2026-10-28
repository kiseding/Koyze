import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'ai_tool_fakes.dart';

/// 校验 `parameters` 里的一层节点，返回它能报出的所有问题。
///
/// 这些规则都来自「网关会怎么挑刺」：`array` 少了 `items`、`required` 里点了
/// 不存在的字段、或者某个属性本身不是对象（例如误把整份 schema 当成一层属性
/// 塞进来），严格的网关会直接回 400，而界面只会说一句「返回内容无法解析」。
List<String> _problemsOf(Object? node, String path) {
  if (node is! Map<String, dynamic>) {
    return ['$path 不是对象：${node.runtimeType}'];
  }
  final type = node['type'];
  if (type == null) return ['$path 缺少 type'];

  switch (type) {
    case 'array':
      if (!node.containsKey('items')) return ['$path 是数组但没有 items'];
      return _problemsOf(node['items'], '$path[]');
    case 'object':
      final properties = node['properties'] ?? const <String, dynamic>{};
      if (properties is! Map) return ['$path 的 properties 不是对象'];
      final problems = <String>[
        for (final entry in properties.entries)
          ..._problemsOf(entry.value, '$path.${entry.key}'),
      ];
      for (final name in (node['required'] as List?) ?? const []) {
        if (!properties.containsKey(name)) {
          problems.add('$path 的 required 里有 $name，但 properties 里没有');
        }
      }
      return problems;
    case 'string':
    case 'integer':
    case 'number':
    case 'boolean':
      return const [];
    default:
      return ['$path 的 type 是 $type'];
  }
}

void main() {
  final specs = ToolFakes().toolbox().specs;
  final names = [
    for (final spec in specs) (spec['function'] as Map)['name'] as String,
  ];

  test('每个工具都能序列化成 function 声明', () {
    expect(specs, isNotEmpty);
    for (final spec in specs) {
      expect(spec['type'], 'function');
      final function = spec['function'] as Map<String, dynamic>;
      expect(function['name'], isA<String>());
      expect((function['name'] as String), isNotEmpty);
      expect((function['description'] as String), isNotEmpty);
    }
  });

  test('工具名不重复', () {
    expect(names.toSet().length, names.length, reason: names.join(', '));
  });

  test('parameters 是合法的 JSON Schema，不会让网关 400', () {
    for (final spec in specs) {
      final function = spec['function'] as Map<String, dynamic>;
      final name = function['name'] as String;
      final parameters = function['parameters'];
      expect(parameters, isA<Map<String, dynamic>>(), reason: name);
      final map = parameters as Map<String, dynamic>;
      expect(map['type'], 'object', reason: '$name 的 parameters.type');
      expect(_problemsOf(map, name), isEmpty);
    }
  });

  test('工具清单不会撑爆上下文', () {
    // 41 个工具的中文描述加起来约 15 KB。再涨到 20 KB 以上，8k 上下文的模型
    // 单是清单就装不下了，这里先拦住。
    final bytes = utf8.encode(jsonEncode(specs)).length;
    expect(bytes, lessThan(20 * 1024), reason: '工具清单 $bytes 字节');
  });
}
