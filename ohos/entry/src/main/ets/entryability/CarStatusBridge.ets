/*
 * Copyright 2024 Koyze Contributors
 * Licensed under the Apache License, Version 2.0
 */

import { Any, BinaryMessenger, EventChannel, EventSink, StreamHandler } from '@ohos/flutter_ohos';
import { smartMobilityCommon } from '@kit.CarKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'KoyzeCar';

/// Dart 侧的 `EventChannel('koyze/car/status')`。
const CHANNEL: string = 'koyze/car/status';

export const CAR_STATE_CONNECTED: string = 'connected';
export const CAR_STATE_DISCONNECTED: string = 'disconnected';
export const CAR_STATE_UNSUPPORTED: string = 'unsupported';

/// 把 HiCar 连接状态抛给 Flutter。
///
/// 只有手机与 HiCar 认证车机（或超级桌面）连上时才成立；能力不支持（模拟器、
/// 平板、低版本系统，错误码 801）时只发一次 `unsupported` 就安静下来，Dart 侧
/// 据此把「车机模式」的自动开关降级掉，不影响其余功能。
///
/// 冷启动兜底：`onListen` 里先主动查一次当前状态再注册监听，否则应用在车机已
/// 连接时启动会一直显示「未连接」，直到下一次连接状态变化。
export default class CarStatusBridge implements StreamHandler {
  private channel: EventChannel | null = null;
  private sink: EventSink | null = null;
  private awareness: smartMobilityCommon.SmartMobilityAwareness | null = null;
  private listening: boolean = false;
  private connected: boolean = false;
  private readonly types: smartMobilityCommon.SmartMobilityType[] = [
    smartMobilityCommon.SmartMobilityType.HICAR,
  ];

  /// 必须留成字段：`off()` 要靠同一个函数引用才能注销。
  private readonly onStatus = (info: smartMobilityCommon.SmartMobilityInfo): void => {
    this.connected = info.status === smartMobilityCommon.SmartMobilityStatus.RUNNING;
    this.emit(this.connected);
  };

  attach(messenger: BinaryMessenger): void {
    const channel = new EventChannel(messenger, CHANNEL);
    channel.setStreamHandler(this);
    this.channel = channel;
  }

  detach(): void {
    this.stopListening();
    this.sink = null;
    // 不调 `setStreamHandler(null)`：签名只接受 StreamHandler，而 ability 正在销毁，
    // 通道本身也会随之消失。
    this.channel = null;
  }

  onListen(args: Any, events: EventSink): void {
    this.sink = events;
    if (this.listening) {
      this.emit(this.connected);
      return;
    }
    try {
      const awareness = smartMobilityCommon.getSmartMobilityAwareness();
      this.awareness = awareness;
      const info = awareness.getSmartMobilityStatus(smartMobilityCommon.SmartMobilityType.HICAR);
      this.connected = info.status === smartMobilityCommon.SmartMobilityStatus.RUNNING;
      awareness.on('smartMobilityStatus', this.types, this.onStatus);
      this.listening = true;
      this.emit(this.connected);
    } catch (error) {
      const failure = error as BusinessError;
      hilog.info(DOMAIN, TAG, 'Car Kit unavailable, code=%{public}d', failure.code);
      events.success(CAR_STATE_UNSUPPORTED);
    }
  }

  onCancel(args: Any): void {
    this.sink = null;
    this.stopListening();
  }

  private stopListening(): void {
    if (!this.listening) return;
    this.listening = false;
    try {
      this.awareness?.off('smartMobilityStatus', this.types);
    } catch (error) {
      const failure = error as BusinessError;
      hilog.warn(DOMAIN, TAG, 'off smartMobilityStatus failed, code=%{public}d', failure.code);
    }
    this.awareness = null;
  }

  private emit(connected: boolean): void {
    this.sink?.success(connected ? CAR_STATE_CONNECTED : CAR_STATE_DISCONNECTED);
  }
}
