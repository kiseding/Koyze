# 贡献指南

感谢您考虑为 Koyze 做贡献！本项目基于 Apache 2.0 许可证开源。

## 📋 行为准则

请遵守我们的 [行为准则](CODE_OF_CONDUCT.md)，营造友好、包容的社区环境。

## 🚀 快速开始

### 前置要求

- **Flutter**: 3.44.0 或更高版本
- **Dart**: 3.12.0 或更高版本
- **Node.js**: 20+ (用于 Workers 开发)
- **Git**: 用于版本控制

### 首次设置

```bash
# 克隆仓库
git clone https://github.com/kiseding/koyze.git
cd koyze

# 安装 Flutter 依赖
flutter pub get

# 运行测试
flutter test --exclude-tags live

# 启动应用（选择平台）
flutter run -d macos    # macOS
flutter run -d windows  # Windows
flutter run -d linux    # Linux
flutter run -d android  # Android
flutter run -d ios      # iOS
```

### Workers 后端开发

```bash
cd workers

# 安装依赖
npm install

# 运行本地开发服务器
npm run dev

# 应用数据库迁移
npx wrangler d1 migrations apply koyze-api --local

# 运行测试
npm test
```

## 🔀 贡献流程

### 1. 创建 Issue

在开始编码前，请先创建或认领一个 Issue：

- **Bug Report**: 使用 [Bug 报告模板](.github/ISSUE_TEMPLATE/bug_report.md)
- **Feature Request**: 使用 [功能请求模板](.github/ISSUE_TEMPLATE/feature_request.md)
- **Documentation**: 直接创建 Issue

### 2. Fork 并创建分支

```bash
# Fork 仓库到你的账号

# 克隆你的 fork
git clone https://github.com/YOUR_USERNAME/koyze.git
cd koyze

# 添加上游仓库
git remote add upstream https://github.com/kiseding/koyze.git

# 创建功能分支
git checkout -b feature/your-feature-name
# 或
git checkout -b fix/bug-description
```

### 3. 分支命名规范

- `feature/xxx` - 新功能
- `fix/xxx` - Bug 修复
- `docs/xxx` - 文档更新
- `refactor/xxx` - 重构
- `test/xxx` - 测试改进
- `perf/xxx` - 性能优化

### 4. 编写代码

#### 代码规范

- 遵循 Dart 官方风格指南
- 使用 `flutter analyze` 检查代码
- 添加必要的注释（特别是复杂逻辑）
- 为公共 API 添加文档注释

```dart
/// 搜索指定平台的歌曲
///
/// [query] 搜索关键词
/// [platform] 音乐平台（QQ音乐、网易云等）
/// [limit] 返回结果数量，默认 30
///
/// 返回 [List<Song>] 搜索结果
/// 抛出 [NetworkException] 网络错误时
Future<List<Song>> search(String query, {
  required MusicPlatform platform,
  int limit = 30,
}) async {
  // ...
}
```

#### 提交规范

遵循 [Conventional Commits](https://www.conventionalcommits.org/)：

```bash
# 格式
<type>(<scope>): <subject>

# 示例
feat(player): 添加歌词翻译功能
fix(android): 修复后台播放崩溃问题
docs(readme): 更新安装说明
test(player): 添加播放器状态机测试
refactor(sync): 简化同步逻辑
perf(search): 优化搜索性能
```

**Type 类型**:
- `feat`: 新功能
- `fix`: Bug 修复
- `docs`: 文档更新
- `style`: 代码格式（不影响功能）
- `refactor`: 重构
- `test`: 测试
- `chore`: 构建/工具配置
- `perf`: 性能优化

### 5. 编写测试

**所有新功能必须包含测试**：

```dart
// test/features/player/player_controller_test.dart
void main() {
  group('PlayerController', () {
    late PlayerController controller;
    late MockAudioService mockAudioService;

    setUp(() {
      mockAudioService = MockAudioService();
      controller = PlayerController(mockAudioService);
    });

    test('should start playing when play() is called', () async {
      final song = createTestSong();
      
      await controller.play(song);
      
      expect(controller.state.isPlaying, true);
      verify(mockAudioService.play(song.url)).called(1);
    });
  });
}
```

运行测试：

```bash
# 运行所有测试
flutter test

# 运行特定测试文件
flutter test test/features/player/player_controller_test.dart

# 生成覆盖率报告
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html
```

### 6. 提交 Pull Request

#### PR 检查清单

在提交 PR 前，确保：

- [ ] 代码通过 `flutter analyze`
- [ ] 所有测试通过 `flutter test`
- [ ] 测试覆盖率未下降（目标 ≥70%）
- [ ] 已更新相关文档
- [ ] 已添加 CHANGELOG 条目
- [ ] Commit 信息遵循规范
- [ ] 分支基于最新的 `main`

#### PR 描述模板

```markdown
## 变更说明
简要描述你的更改

## 相关 Issue
Closes #123

## 变更类型
- [ ] Bug 修复
- [ ] 新功能
- [ ] 破坏性变更
- [ ] 文档更新

## 测试
描述你如何测试这些更改：
- [ ] 单元测试
- [ ] 集成测试
- [ ] 手动测试

## 截图（如适用）
添加截图展示 UI 变更

## 检查清单
- [ ] 代码遵循项目风格
- [ ] 已添加测试
- [ ] 所有测试通过
- [ ] 已更新文档
```

## 🧪 测试策略

### 单元测试
测试独立的函数、类：

```dart
test('should parse song metadata correctly', () {
  final metadata = parseSongMetadata(testData);
  
  expect(metadata.title, '七里香');
  expect(metadata.artist, '周杰伦');
});
```

### Widget 测试
测试 UI 组件：

```dart
testWidgets('should display song title', (tester) async {
  await tester.pumpWidget(SongCard(song: testSong));
  
  expect(find.text('七里香'), findsOneWidget);
});
```

### 集成测试
测试完整用户流程：

```dart
// integration_test/app_test.dart
testWidgets('complete search and play flow', (tester) async {
  await tester.pumpWidget(MyApp());
  
  // 搜索
  await tester.enterText(find.byType(SearchBar), '周杰伦');
  await tester.tap(find.byIcon(Icons.search));
  await tester.pumpAndSettle();
  
  // 播放
  await tester.tap(find.byType(SongCard).first);
  await tester.pumpAndSettle();
  
  expect(find.byType(PlayerBottomBar), findsOneWidget);
});
```

## 📝 文档贡献

### API 文档
为公共 API 添加文档注释：

```dart
/// 音乐源抽象接口
///
/// 所有音乐平台（QQ音乐、网易云等）都实现此接口
abstract class MusicSource {
  /// 搜索歌曲
  ///
  /// 返回包含 [Song] 对象的列表
  /// 如果网络错误，抛出 [NetworkException]
  Future<List<Song>> search(String query, {int limit = 30});
}
```

### README 更新
如果你的更改影响用户使用方式，请更新 README.md

### ADR（架构决策记录）
重大架构决策请创建 ADR 文档：

```bash
cp docs/adr/template.md docs/adr/NNNN-your-decision.md
# 编辑 ADR 文档
```

## 🎨 代码风格

### Dart 风格
- 使用 `flutter analyze` 检查
- 变量/函数使用 `camelCase`
- 类名使用 `PascalCase`
- 常量使用 `lowerCamelCase`
- 私有成员使用 `_leading` 下划线

### 组织结构
```
lib/
├── core/           # 核心功能、模型、服务
├── features/       # 功能模块（按领域划分）
│   └── player/
│       ├── domain/        # 业务逻辑
│       ├── data/          # 数据层
│       └── presentation/  # UI 层
└── router/         # 路由配置
```

## 🐛 报告 Bug

使用 [Bug 报告模板](.github/ISSUE_TEMPLATE/bug_report.md)，包含：

- **复现步骤**: 详细的操作步骤
- **期望行为**: 应该发生什么
- **实际行为**: 实际发生了什么
- **环境信息**: 
  - 操作系统
  - Koyze 版本
  - Flutter 版本
- **日志**: 相关错误日志
- **截图**: 如果适用

## 💡 功能建议

使用 [功能请求模板](.github/ISSUE_TEMPLATE/feature_request.md)，说明：

- **问题描述**: 你想解决什么问题？
- **建议方案**: 你期望的解决方案
- **替代方案**: 其他可能的方案
- **用例**: 实际使用场景

## 📞 获取帮助

- **GitHub Discussions**: [讨论区](https://github.com/kiseding/koyze/discussions)
- **Issue Tracker**: [问题追踪](https://github.com/kiseding/koyze/issues)
- **Telegram 群组**: [Koyze 中文群](https://t.me/koyze_cn) (如果有)

## 🎉 贡献者名单

感谢所有贡献者！你的名字将出现在 [Contributors](https://github.com/kiseding/koyze/graphs/contributors) 页面。

## 📄 许可证

贡献到本项目的所有代码将以 Apache 2.0 许可证发布。

通过提交 Pull Request，你同意：
- 你的贡献按 Apache 2.0 许可证授权
- 你拥有提交代码的权利
- 你授予项目永久、全球、非独占的使用权

---

再次感谢你的贡献！🎵
