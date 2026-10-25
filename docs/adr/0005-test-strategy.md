# ADR-0005: 测试策略 —— 什么样的断言才算数

## 状态

已接受（2026-10-26）

## 上下文

项目有 172 个测试文件、44,236 行测试代码、约 1,586 个测试用例，
测试/生产代码比约 53%。这个比例在个人 Flutter 项目里非常罕见。

但审查发现了一个结构性问题：**相当一部分测试根本不是在测行为。**

典型形态：

```dart
test('play mode icons keep their intended direction while switching', () {
  final source = File('lib/features/player/presentation/player_screen.dart')
      .readAsStringSync();
  expect(source, contains('return Icons.repeat;'));
  expect(source, isNot(contains('return Icons.trending_flat')));
});
```

这个测试测的是「文件里有没有这行字」，它：

- **在逻辑被改坏时可能仍然通过** —— 只要那行字还在，即使 `_getPlayModeIcon`
  被改成永远返回同一个图标、或者根本没被调用
- **在无害重构时必然失败** —— 重命名变量、调整缩进、提取方法、换个写法都会红
- **在 Windows 上必然失败** —— `readAsStringSync()` 返回 CRLF，而断言里写的是 `\n`

问题最严重的一个文件有 8 个测试、80+ 条字符串断言，全部指向同一个实现文件。
它给人的印象是"播放器转场有充分保护"，实际上只要重构就全红，而功能真坏掉时
不一定红。

## 决策

把测试分为三类，分别对待。

### 第一类：行为测试（应当成为主体）

**特征**：实例化真实对象、调用真实方法、断言可观察的输出。

```dart
expect(nextPlayMode(PlayMode.repeatOne), PlayMode.sequential);
```

**本次改造示例**（原 grep 断言 → 行为断言）：

| 原测试 | 改造后 |
| --- | --- |
| 源码里有 `Icons.repeat` | `nextPlayMode` / `playModeIcon` 共 10 个断言，覆盖状态机、图标映射、从 PlaybackState 反推 |
| 源码里有 `activeColor: accent` | 渲染真实 `LyricView`，读 `DefaultTextStyle` 的实际颜色，4 个断言含浅色主题 |
| 源码里有 `Rect.lerp` | 构造真实路由，断言 `opaque` / `barrierDismissible` / `pageKey` 记忆行为 |
| 源码里有 `kMiniBarHeight = 66` | 直接测 `KoyzeMiniBarMetrics` 的 8 个几何输出 |
| 源码里有 `Positioned.fromRect` | 遍历渲染树，断言 morph 矩形随 progress 单调变大 |

**为了可测性做的生产代码调整**（顺带改善了设计）：

- `PlayMode` 的 `_getNextPlayMode` / `_getPlayModeIcon` 从 `_PlayerScreenState`
  的私有方法提升为 `player_provider.dart` 的模块级公开函数 `nextPlayMode` /
  `playModeIcon`。状态机本来就不该藏在 Widget 私有方法里。

### 第二类：跨文件一致性（保留，但必须归一化换行）

**特征**：断言两个或多个文件里的同一份事实彼此一致。这类没有"行为"可测。

例子：

- `app_version_test` —— Dart 常量、`pubspec.yaml`、`pubspec_ohos.yaml`、
  `ohos/AppScope/app.json5` 四处的版本号必须相同，`versionCode` 必须等于
  `major*1e6 + minor*1e3 + patch`
- `build_configuration_test` —— 所有平台 workflow 必须锁同一个 Flutter 版本
- `android_pigeon_jni_proguard_test` —— `proguard-rules.pro` 必须保留 Pigeon JNI
  用到的 Kotlin 类型，否则 release 包启动即崩

这些是**真实存在的故障模式**，且无法用运行时测试覆盖（Pigeon 的问题只在
release 构建 + 真机上暴露）。保留，但改用 `test/support/source_text.dart` 的
`readSource()`，它会把 CRLF 归一化为 LF。

### 第三类：脆弱的结构断言（删除）

**特征**：断言"某个变量名/某行代码/某个方法顺序仍然存在"，而这些都不是外部契约。

例子（本次删除）：

- `main_playback_authority_test` 断言 `lib/main.dart` 里
  `read(wifiOnlyDownloadProvider.notifier)` 出现在
  `read(downloadServiceProvider).init()` **之前**。这只锁定了语句顺序，
  完全不保证"设置真的在恢复播放前生效"——而那才是注释声称要保护的东西。
- `player_expand_test` 里 80+ 条 `contains('...')` 断言（已整体重写为 7 个
  真实 widget 测试）。
- `home_screen_test` 里断言 `title: 'Koyze'` 字面量存在。

判断标准：**如果删掉这条断言，会不会有某个真实 bug 溜过去？** 如果答案是
"不会"，这条断言就不该存在。

## 关于换行符

`.gitattributes` 强制 `* text=auto eol=lf`，Dart / TS / YAML 一律 LF。
`.bat` / `.cmd` / `.ps1` 保持 CRLF。

这解决了根本问题，但**不能只靠它**：

1. 已经克隆的仓库不会因为新增 `.gitattributes` 自动重写工作区文件
2. 有些场景（比如 Windows 上的某些编辑器）会重新引入 CRLF

所以 `readSource()` 的归一化是必需的防御层，两层一起才有意义。

## 后果

### 正面

- 测试失败时的信号变清晰：红了说明行为变了，不再是"有人改了格式"
- 该红的时候会红：原来 `play_mode_icon_test` 在图标被改成永远返回同一个时
  不会失败，现在会
- Windows 开发者本地能跑通全量测试，不再需要"这是 CRLF 问题"的解释

### 负面

- 改造后总断言数下降。这不是退步——原来的数字里有一部分是噪音
- 部分结构护栏确实被删掉了，理论上存在"某个约束被悄悄改掉"的风险。
  缓解方式：把真正重要的约束写成注释留在代码里，并在 PR review 时人工确认
- 新增了 `test/support/` 目录，需要团队知道它的存在

### 未做的事

- **没有追求覆盖率数字。** `flutter test --coverage` 能给出的行覆盖率对
  Flutter UI 代码意义有限，本项目也没有配置覆盖率门禁
- **没有给所有 `_` 私有 Widget 补测试。** 私有实现细节不该被测试锁死；
  测试应该对着公开入口打
- **没有删除全部结构断言。** 第二类（跨文件一致性、构建配置契约）是合理的，
  一刀切删掉会丢掉真实保护

## 相关

- `docs/adr/0004-dependency-upgrade-strategy.md` —— 拆分 `audio_handler`
  需要真实的行为测试才有安全网，这是本文档的前置依赖
- `test/support/source_text.dart` —— 归一化读取工具
- `.gitattributes` —— 换行符策略
