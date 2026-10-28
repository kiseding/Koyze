
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import CarStatusBridge from './CarStatusBridge';

export default class EntryAbility extends FlutterAbility {
  private carStatus: CarStatusBridge | null = null;

  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    // HiCar 连接状态。Car Kit 缺失或设备不支持时这一路只发一次 unsupported，
    // 由 Dart 侧把「车机模式」的自动开关降级掉。
    const bridge = new CarStatusBridge();
    bridge.attach(flutterEngine.getDartExecutor().getBinaryMessenger());
    this.carStatus = bridge;
  }

  onDestroy(): void {
    this.carStatus?.detach();
    this.carStatus = null;
    super.onDestroy();
  }
}
