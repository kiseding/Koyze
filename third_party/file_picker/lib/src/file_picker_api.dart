import 'dart:typed_data';

import 'package:file_picker/src/file_picker.dart';
import 'package:file_picker/src/file_picker_result.dart';

/// Static facade over [FilePickerPlatform].
///
/// file_picker >= 11 exposes its API as static methods on `FilePicker`
/// (`FilePicker.pickFiles(...)`), while this OpenHarmony port (10.3.8)
/// still exposes them as instance methods on `FilePickerPlatform.platform`.
/// Keeping the same static surface here lets application code compile
/// unchanged against both the official package and this port.
abstract final class FilePicker {
  static FilePickerPlatform get _platform => FilePickerPlatform.platform;

  /// Retrieves the file(s) from the underlying platform.
  static Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) =>
      _platform.pickFiles(
        dialogTitle: dialogTitle,
        initialDirectory: initialDirectory,
        type: type,
        allowedExtensions: allowedExtensions,
        onFileLoading: onFileLoading,
        allowCompression: allowCompression,
        compressionQuality: compressionQuality,
        allowMultiple: allowMultiple,
        withData: withData,
        withReadStream: withReadStream,
        lockParentWindow: lockParentWindow,
        readSequential: readSequential,
      );

  /// Asks the underlying platform to remove any temporary files created by this plugin.
  static Future<bool?> clearTemporaryFiles() => _platform.clearTemporaryFiles();

  /// Selects a directory and returns its absolute path.
  static Future<String?> getDirectoryPath({
    String? dialogTitle,
    bool lockParentWindow = false,
    String? initialDirectory,
  }) =>
      _platform.getDirectoryPath(
        dialogTitle: dialogTitle,
        lockParentWindow: lockParentWindow,
        initialDirectory: initialDirectory,
      );

  /// Displays a dialog that allows the user to select both files and directories.
  static Future<List<String>?> pickFileAndDirectoryPaths({
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    String? initialDirectory,
  }) =>
      _platform.pickFileAndDirectoryPaths(
        type: type,
        allowedExtensions: allowedExtensions,
        initialDirectory: initialDirectory,
      );

  /// Opens a save file dialog which lets the user select a file path and a file name.
  static Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) =>
      _platform.saveFile(
        dialogTitle: dialogTitle,
        fileName: fileName,
        initialDirectory: initialDirectory,
        type: type,
        allowedExtensions: allowedExtensions,
        bytes: bytes,
        lockParentWindow: lockParentWindow,
      );
}
