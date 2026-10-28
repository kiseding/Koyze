// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'ai_agent.dart';
import 'ai_config.dart';
import 'ai_tools.dart';

enum AiChatRole { user, assistant }

/// 对话里的一条消息。助手消息可以带一串工具执行记录。
class AiChatEntry {
  const AiChatEntry({
    required this.role,
    this.text = '',
    this.toolRuns = const <AiToolRun>[],
    this.failure,
    this.detail,
    this.scheduleTitle,
    this.voiceSeconds,
    this.voiceBytes,
    this.voiceLost = false,
  });

  final AiChatRole role;
  final String text;
  final List<AiToolRun> toolRuns;

  /// 非空表示这条消息带了一段语音，值是秒数。气泡里据此显示一个语音标签——
  /// 录音发完就删，气泡不能再点开听，所以只报时长。
  final int? voiceSeconds;

  /// 实际发出去的录音字节数。气泡里一并标出来，用来回答「文件到底传没传」：
  /// 只要这个数在，音频就进了请求体，剩下收不到就是接口那边丢了。
  final int? voiceBytes;

  /// 这一轮带了录音，但模型的回复说明它没收到音频。
  ///
  /// 只在助手气泡上用：用户看到的是「我明明录了它却说没有」，界面得指出
  /// 这是接口把音频丢了，而不是用户的录音有问题。
  final bool voiceLost;

  /// 非空表示这条回复是定时任务自己跑出来的，界面会在气泡上标一条来源。
  final String? scheduleTitle;

  /// 非空表示这一轮请求失败，[text] 里没有内容。
  final AiFailureKind? failure;

  /// 接口的原话（例如 `context_length_exceeded: ...`）。有就在气泡里附一行，
  /// 光给一句「返回内容无法解析」用户没法判断该改什么。
  final String? detail;

  bool get isUser => role == AiChatRole.user;
}

class AiChatState {
  const AiChatState({
    this.entries = const <AiChatEntry>[],
    this.busy = false,
    this.activeTool,
  });

  final List<AiChatEntry> entries;
  final bool busy;

  /// 正在执行哪一类工具，界面据此显示「正在播放控制…」。
  final AiToolCategory? activeTool;

  bool get isEmpty => entries.isEmpty;

  AiChatState copyWith({
    List<AiChatEntry>? entries,
    bool? busy,
    AiToolCategory? activeTool,
    bool clearActiveTool = false,
  }) => AiChatState(
    entries: entries ?? this.entries,
    busy: busy ?? this.busy,
    activeTool: clearActiveTool ? null : (activeTool ?? this.activeTool),
  );
}
