/// 音源脚本的「同步死循环」预检。
///
/// 只拦**静态可证**的同步死循环：恒真循环（`while(true)` / `for(;;)` /
/// `do..while(true)`）里一条出口（`break` / `return` / `throw`）都没有时，
/// 脚本一进运行时就会把 isolate 卡死，而 QuickJS/JSC 一旦开始 evaluate 就
/// 没法中断，所以只能在执行前拒掉。
///
/// 改动前先看这段历史 —— 下面这些规则是**故意**留了余量的，不是漏网：
///
/// * 2026-11 之前 `while(<恒真>)` 是「见到就拒」，而恒真集合里含 `!![]`。
///   javascript-obfuscator 的字符串数组轮转恰好长这样：
///   `while(!![]){try{...if(x===y)break;else a.push(a.shift())}catch{...}}`
///   —— 它靠 `break` 退出。结果 fish / flower / grass / sixyin / yuningxi
///   这些正常音源一导入就报「初始化失败，请检查脚本」。现在改成看循环里
///   有没有出口（[_hasUnboundedTruthyLoop]）。
/// * 同一版还有一条「反调试组合」判据（`['push'](` + `['length']` +
///   改写循环边界 + `['toString']()` + `new RegExp(` + `for(`）。它描述的是
///   混淆器指纹而不是循环形状，过 javascript-obfuscator 的脚本几乎全中，
///   fish 就是被它挡住的。已删除，不要加回来。
/// * 递归判据曾把 `const md5 = (s) => utils.crypto.md5(s)` 这种包装函数当成
///   自递归，现在只认直接调用，见 [_hasBareSelfCall]。
///
/// 增长型循环（`for(...; i<n; ...){ arr.push(x); n = arr.length; }`）**不**在
/// 这个函数里判，原因见 [hasSynchronousGrowthLoop]。
///
/// 这个启发式不是沙箱，也不能用来「授权」执行：它只负责拦已知会卡死的形状。
bool hasUnsafeSynchronousLoop(String script) {
  final code = _withoutCommentsAndStrings(
    script,
  ).replaceAll(RegExp(r'\s+'), '');
  // These conditions are statically truthy and do not depend on runtime
  // input. Detect the common minified forms as well as `true` so they never
  // reach a runtime that cannot interrupt synchronous JavaScript evaluation.
  final alwaysTrueCondition =
      r'(?:true|1|[1-9]\d*|-1|0x[1-9a-f][0-9a-f]*|!0|!!\[\]|\[\])';
  if (_hasUnboundedTruthyLoop(code, 'while\\($alwaysTrueCondition\\)') ||
      _hasUnboundedTruthyLoop(code, r'for\(;;\)') ||
      _hasUnboundedDoWhile(code, alwaysTrueCondition)) {
    return true;
  }
  final recursive = RegExp(
    r'(?:function([\w$]+)|([\w$]+)=function)\([^)]*\)\{([^{}]{0,1600})\}',
  );
  for (final match in recursive.allMatches(code)) {
    final name = match.group(1) ?? match.group(2);
    final body = match.group(3)!;
    if (name != null &&
        _hasBareSelfCall(body, name) &&
        !body.contains('if(') &&
        !RegExp(r'\b(?:while|for)\(').hasMatch(body)) {
      return true;
    }
  }
  final arrowRecursive = RegExp(
    r'(?:const|let|var)([\w$]+)=\([^)]*\)=>(?:\{)?([^{};]{0,800})',
  );
  for (final match in arrowRecursive.allMatches(code)) {
    if (_hasBareSelfCall(match.group(2)!, match.group(1)!)) {
      return true;
    }
  }
  return false;
}

/// 边遍历边增长的循环：`for(...; i<n; ...){ arr.push(x); n = arr.length; }`。
///
/// 这类循环的上界在循环体里被重新写成集合长度，静态看就是停不下来的同步增长。
/// 但它**故意不作为拒绝执行的依据**，别再把它接回 [hasUnsafeSynchronousLoop]：
/// javascript-obfuscator 的 debug-protection 陷阱就是这个形状，fish 里也带着
/// 一段（`prototype.aScjtT`），只有脚本检测到自己被篡改时才会走进去，正常加载
/// 根本执行不到。按它硬拒等于把绝大多数社区音源一起拉黑 —— 旧版的「反调试
/// 组合」判据就是这么把 fish 挡在外面的。
///
/// 现在的用法是诊断信号：引擎加载时打一条 `synchronous_growth_loop`，
/// 用户真遇到「卡住」时可以据此判断脚本里有什么。
bool hasSynchronousGrowthLoop(String script) {
  final compact = script.replaceAll(RegExp(r'\s+'), '');
  final forLoops = RegExp(
    r'for\(([^;]*);([^;]*);[^)]*\)\{([^{}]{0,1200})\}',
  );
  for (final match in forLoops.allMatches(compact)) {
    final bound = RegExp(r'[\w$]+<=?([\w$]+)').firstMatch(match.group(2)!);
    if (bound == null) continue;
    final name = RegExp.escape(bound.group(1)!);
    if (RegExp('$name=[^;{}]{0,80}length').hasMatch(match.group(3)!)) {
      return true;
    }
  }
  return false;
}

/// `while(<恒真>)` / `for(;;)` 只有在循环体里没有任何出口
/// （`break` / `return` / `throw`）时才是必然死循环。
///
/// javascript-obfuscator 的字符串数组轮转恰好是这两种形状：
/// `while(!![]){try{...if(x===y)break;else arr.push(arr.shift())}catch(e){...}}`，
/// 校验和匹配后会 `break`，属于正常的初始化代码。把它当成死循环直接拒绝执行，
/// 会让 fish / flower / sixyin / grass / yuningxi 这类混淆音源全部无法加载。
///
/// 这里不按大括号配对取循环体：`_withoutCommentsAndStrings` 只是粗粒度的
/// 词法剥离（正则字面量、模板字符串里的花括号都可能留下残渣），640 KB 的
/// 混淆脚本上配对会失准，取不到循环体。改成看循环头之后固定窗口内有没有出口，
/// 窗口取 [_loopExitWindow]，足够覆盖混淆器轮转体的实际长度。
bool _hasUnboundedTruthyLoop(String code, String headerPattern) {
  for (final match in RegExp(headerPattern).allMatches(code)) {
    final end = match.end + _loopExitWindow;
    final window = code.substring(
      match.end,
      end < code.length ? end : code.length,
    );
    if (!RegExp(r'\b(?:break|return|throw)\b').hasMatch(window)) return true;
  }
  return false;
}

/// `do{...}while(<恒真>)` 同样要看循环体里有没有出口。
bool _hasUnboundedDoWhile(String code, String alwaysTrue) {
  final pattern = RegExp('do\\{([^{}]{0,400})\\}while\\($alwaysTrue\\)');
  for (final match in pattern.allMatches(code)) {
    if (!RegExp(r'\b(?:break|return|throw)\b').hasMatch(match.group(1)!)) {
      return true;
    }
  }
  return false;
}

/// 判定恒真循环是否「无出口」时向后看的字符数。混淆器的轮转体实测 400~1900 字符。
const int _loopExitWindow = 4096;

/// [body] 里是否存在对 [name] 的**直接**调用。
///
/// `utils.crypto.md5(str)`、`Buffer.isBuffer(obj)` 这类属性访问不算自递归。
/// 否则 `const md5 = (s) => utils.crypto.md5(s)` 这种普通包装函数会被误判成
/// 递归死循环（jiexiang、xinghai 就栽在这里）。
///
/// 注意 [body] 已经去掉空白，`return a()` 会变成 `returna()`，所以这里只排除
/// 紧贴 `.` 的属性调用，不能按「前一个字符是标识符」判否，否则真正的递归
/// `function a(){return a()}` 会漏掉。
bool _hasBareSelfCall(String body, String name) {
  for (final match in RegExp('${RegExp.escape(name)}\\(').allMatches(body)) {
    if (match.start == 0) return true;
    if (body.codeUnitAt(match.start - 1) != 0x2E) return true;
  }
  return false;
}

String _withoutCommentsAndStrings(String source) {
  final output = StringBuffer();
  var quote = 0;
  var lineComment = false;
  var blockComment = false;
  var escaped = false;
  for (var i = 0; i < source.length; i++) {
    final char = source.codeUnitAt(i);
    final next = i + 1 < source.length ? source.codeUnitAt(i + 1) : 0;
    if (lineComment) {
      if (char == 10 || char == 13) {
        lineComment = false;
        output.writeCharCode(char);
      }
      continue;
    }
    if (blockComment) {
      if (char == 42 && next == 47) {
        blockComment = false;
        i++;
      }
      continue;
    }
    if (quote != 0) {
      if (escaped) {
        escaped = false;
      } else if (char == 92) {
        escaped = true;
      } else if (char == quote) {
        quote = 0;
      }
      continue;
    }
    if (char == 47 && next == 47) {
      lineComment = true;
      i++;
    } else if (char == 47 && next == 42) {
      blockComment = true;
      i++;
    } else if (char == 34 || char == 39 || char == 96) {
      quote = char;
    } else {
      output.writeCharCode(char);
    }
  }
  return output.toString();
}
