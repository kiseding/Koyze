
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import CarStatusBridge from './CarStatusBridge';
import ClipboardBridge from './ClipboardBridge';
import LocalFileSystemBridge from './LocalFileSystemBridge';
import MethodChannel from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import StandardMethodCodec from '@ohos/flutter_ohos/src/main/ets/plugin/common/StandardMethodCodec';

export default class EntryAbility extends FlutterAbility {
  private carStatus: CarStatusBridge | null = null;
  private fileSystemChannel: MethodChannel | null = null;
  private clipboardChannel: MethodChannel | null = null;

  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    // HiCar 连接状态。Car Kit 缺失或设备不支持时这一路只发一次 unsupported，
    // 由 Dart 侧把「车机模式」的自动开关降级掉。
    const bridge = new CarStatusBridge();
    bridge.attach(flutterEngine.getDartExecutor().getBinaryMessenger());
    this.carStatus = bridge;
    // 本地音乐文件管理。方法名与参数名和 Android / iOS 完全一致，
    // Dart 侧三个平台共用一个解析实现。
    const fileChannel = new MethodChannel(
      flutterEngine.getDartExecutor().getBinaryMessenger(),
      'koyze/local_file_system',
      StandardMethodCodec.INSTANCE,
    );
    fileChannel.setMethodCallHandler(new LocalFileSystemBridge(this.context));
    this.fileSystemChannel = fileChannel;
    // 剪贴板。Flutter 自带的 Clipboard 通道在鸿蒙引擎上没有实现，
    // 且是 OptionalMethodChannel，失败时静默返回 null，只能自己补。
    const clipboardChannel = new MethodChannel(
      flutterEngine.getDartExecutor().getBinaryMessenger(),
      'koyze/clipboard',
      StandardMethodCodec.INSTANCE,
    );
    clipboardChannel.setMethodCallHandler(new ClipboardBridge(this.context));
    this.clipboardChannel = clipboardChannel;
  }

  onDestroy(): void {
    this.carStatus?.detach();
    this.carStatus = null;
    this.fileSystemChannel?.setMethodCallHandler(null);
    this.fileSystemChannel = null;
    this.clipboardChannel?.setMethodCallHandler(null);
    this.clipboardChannel = null;
    super.onDestroy();
  }
}
