import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String source;

  setUpAll(() {
    source = File(
      'lib/features/local_music/presentation/scan_rules_sheet.dart',
    ).readAsStringSync();
  });

  test('扫描规则的排除目录走系统文件夹选择器，不再手动输入路径', () {
    expect(source, contains('FilePicker.getDirectoryPath'));
    expect(source, contains('dialogTitle: s.scanRuleAddFolder'));
    expect(source, isNot(contains('showDialog<String>')));
    expect(source, isNot(contains('TextField(')));
    expect(source, isNot(contains('TextEditingController')));
  });

  test('原生目录选择通道按平台分派，失败时给出提示', () {
    expect(source, contains('localFileSystemProvider'));
    expect(source, contains('fs.needsNativeDirectoryPicker'));
    expect(source, contains('await fs.pickDirectory()'));
    expect(source, contains('s.chooseFolderFailed'));
    expect(source, contains('AppNotificationType.error'));
  });

  test('重复目录按规范化前缀判断，覆盖大小写与斜杠差异', () {
    expect(source, contains('rules.excludes(folder)'));
    expect(source, isNot(contains('excludedFolders.contains(path)')));
  });

  test('添加入口与已排除列表都带文件夹图标', () {
    expect(source, contains('Icons.folder_open_rounded'));
    expect(source, contains('Icons.folder_outlined'));
  });

  test('弹窗布局与其它面板一致：统一标题 + 动作行，没有抓手和裸 Chip/Switch', () {
    expect(source, contains('KoyzeSheetTitle('));
    expect(source, contains('KoyzeSheetAction('));
    expect(source, isNot(contains('KoyzeSheetGrabber')));
    expect(source, isNot(contains('ChoiceChip')));
    expect(source, isNot(contains('FxSwitchTile')));
    expect(source, isNot(contains('OutlinedButton.icon')));
  });

  test('时长与体积进同款单选面板，主面板不再平铺所有选项', () {
    expect(source, contains('_showOptionSheet('));
    expect(source, contains('options: _durationOptions'));
    expect(source, contains('options: _sizeOptions'));
    expect(source, contains('Icons.check_rounded'));
    expect(source, contains('Icons.chevron_right_rounded'));
  });
}
