// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'ai_client.dart';
import 'ai_config.dart';
import 'ai_tools.dart';

/// 一次工具执行的记录，界面拿它显示「AI 做了什么」。
class AiToolRun {
  const AiToolRun({
    required this.name,
    required this.category,
    required this.arguments,
    required this.output,
    required this.ok,
  });

  final String name;
  final AiToolCategory category;
  final Map<String, dynamic> arguments;

  /// 原样回给模型的 JSON，失败时里面带 `error`。
  final String output;
  final bool ok;
}

class AiAgentReply {
  const AiAgentReply({required this.text, required this.toolRuns});

  final String text;
  final List<AiToolRun> toolRuns;
}

/// 会动手的对话代理：模型说要做什么，[AiToolbox] 就在服务层执行。
///
/// 每一轮工具调用的结果都回填给模型，它看过之后接着决定下一步或给出结论；
/// 轮数有上限，避免模型一直查下去。
class AiAgent {
  AiAgent({AiClient? client}) : _client = client ?? AiClient();

  final AiClient _client;

  static const int maxToolRounds = 8;

  static String systemPrompt(AiToolbox toolbox, {bool useTools = true}) {
    final permission = !useTools
        ? '用户关闭了工具调用：只能聊天和给建议，不要假装已经执行。'
        : toolbox.allowActions
        ? '用户已授权你直接执行操作（播放、建单、收藏、下载、删除都会真的生效）。'
        : '用户关闭了执行权限：只能查询和给建议，不要假装已经执行。';
    return '''
你是 Koyze 的应用助手。Koyze 是本地优先的音乐播放器，你可以直接操作用户的应用，不需要用户自己去点界面。
$permission

工作方式：
1. 用户要做什么，就直接调用对应工具把它做完，不要只描述步骤。
2. 播歌、加歌单、收藏、下载之前，先用 search_library 确认这首歌在曲库里真的存在；搜不到就换一首或如实说明，不要凭记忆编歌名。
3. 一次回复里可以连续调用多个工具，全部做完再总结。同一件事不要重复调用。
4. 删除歌单、移除歌曲、清空缓存、停用音源这类不可撤销的操作，只有用户在本轮明确要求时才执行；意图含糊时先用一句话问清楚。
5. 工具返回 error 时，按错误换参数最多重试一次；仍然失败就如实告诉用户，不要编造成功。
6. 回复用用户的语言，简短直给：说清做了什么、影响了几首歌或哪个歌单。不要输出 JSON、工具名或参数。

当前状态：${toolbox.stateLine}''';
  }

  Future<AiAgentReply> run({
    required AiConfig config,
    required String apiKey,
    required List<AiMessage> history,
    required AiToolbox toolbox,
    AiToolObserver? onToolCall,
    bool useTools = true,
    int maxToolRounds = AiAgent.maxToolRounds,
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final tools = useTools ? toolbox.specs : const <Map<String, dynamic>>[];
    final messages = <AiMessage>[
      AiMessage(AiRole.system, systemPrompt(toolbox, useTools: useTools)),
      ...history,
    ];
    final runs = <AiToolRun>[];

    for (var round = 0; round < maxToolRounds; round++) {
      final completion = await _client.completeDetailed(
        config: config,
        apiKey: apiKey,
        messages: messages,
        tools: tools,
        timeout: timeout,
      );
      if (!completion.hasToolCalls) {
        return AiAgentReply(text: completion.content.trim(), toolRuns: runs);
      }

      messages.add(
        AiMessage(
          AiRole.assistant,
          completion.content,
          toolCalls: completion.toolCalls,
        ),
      );
      for (final call in completion.toolCalls) {
        onToolCall?.call(call);
        final output = await toolbox.call(call);
        messages.add(AiMessage.tool(output, toolCallId: call.id));
        runs.add(
          AiToolRun(
            name: call.name,
            category:
                toolbox.toolNamed(call.name)?.category ??
                AiToolCategory.library,
            arguments: call.arguments,
            output: output,
            ok: !output.contains('"error"'),
          ),
        );
      }
    }
    throw const AiException(AiFailureKind.badResponse, '工具调用轮数超过上限');
  }
}
