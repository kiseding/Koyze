# ADR-0006: 删除 `EnhancedScriptValidator` 死代码

- 状态：已采纳
- 日期：2026-10-26

## 背景

`lib/features/custom_source/domain/enhanced_script_validator.dart`（317 行）
实现了一套看起来相当完整的安全校验：

- 静态 AST 级别的动态代码执行检测（`eval`、`new Function`、`constructor` 反射）
- 禁用全局对象检测（`process`、`require`、`child_process`、`fs`）
- 混淆与熵分析（Shannon 熵 > 5.5 判为疑似混淆）
- 复杂度估算
- 长 base64 串检测

配套测试 `enhanced_script_validator_test.dart` 有 322 行、21 个用例，全部通过。

## 问题

**这套校验从未被任何生产代码调用。**

`grep -rn "EnhancedScriptValidator" lib` 的唯一命中是它自己的定义。
`ValidationResult` / `SecurityIssue` / `SecurityLevel` 也没有任何外部引用。

真正在导入路径上生效的是
`lib/features/custom_source/domain/source_script_safety.dart` 里的
`hasUnsafeSynchronousLoop`——一个纯粹用来检测「同步死循环」的启发式，
它的文档注释已经明确写了 *This heuristic is not a sandbox and must never
authorize script execution.*

也就是说：项目里存在一个**看起来提供多层安全防护、实际上不参与运行**的模块，
外加 21 个让它显得「被验证过」的测试。

这比没有这个模块更糟糕，原因有三：

1. **虚假安全感**。代码审查者看到 `EnhancedScriptValidator` 和它的测试，
   会认为自定义音源的脚本导入有安全把关。实际上没有任何把关。
2. **维护成本**。317 行 + 322 行测试会随着语言和 lint 演进持续产生噪音
   （升级 Dart 时它需要跟着改），但不产生任何收益。
3. **误导后续开发**。下一个接手的人可能「修好」它的某个正则，以为在加固安全，
   实际上改的是一段死代码。

## 决策

**删除该模块及其测试**，不做「接入」处理。

考虑过接入，但评估后否决：

- 它的核心检测手段是**字符串正则匹配**，而 JS 有无数种等价写法
  （`globalThis['ev'+'al']`、`(0,eval)`、`Reflect.construct`）。
  正则黑名单在对抗性场景下必然被绕过，接入它只会把「无防护」包装成
  「有防护」，比现状更危险。
- 它的**熵分析会大量误报**：压缩后的正常音源脚本熵值普遍在 5.5 以上，
  接入后会把绝大多数合法音源判为高危。
- 项目已经在 4.1.0 主动移除了内置取址逻辑，自定义音源本身就是「用户自行导入、
  后果自负」的功能，README 已明确声明「这不是安全沙箱」。

如果将来要真正做脚本隔离，正确方向是**进程/VM 级隔离**（把 JS 运行时放进
独立进程并施加 CPU 与内存配额），而不是在 Dart 侧做正则审计。这件事需要单独立项，
不应由一个已有的死模块来假装完成。

## 影响

- 净删除 639 行代码。
- `flutter analyze` 无新增告警。
- 导入用户脚本的**实际安全姿态不变**——因为这段代码本来就没生效。
  变的只是「代码库不再宣称自己有它没有的能力」。

## 遗留

`source_script_safety.dart` 的 `hasUnsafeSynchronousLoop` 保留。它是**诊断**用途
（帮助用户在导入时发现自己写了死循环），不是安全边界，其注释已如实说明这一点。
