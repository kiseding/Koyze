/*
 * Copyright (C) 2024 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { StreamHandler, EventSink } from '@ohos/flutter_ohos/src/main/ets/plugin/common/EventChannel';
import { Connectivity } from './Connectivity';
import { ArrayList } from '@kit.ArkTS';

//创建tag
const TAG = "ConnectivityBroadcastReceiver";

//创建类
export class ConnectivityBroadcastReceiver implements StreamHandler {
  private connectivity: Connectivity;
  private context: Context;
  private events: EventSink | null = null;

  constructor(context: Context, connectivity: Connectivity) {
    this.context = context;
    this.connectivity = connectivity;
  }

  onListen(args: Object, events: EventSink): void {
    this.events = events;

    Connectivity.netConnection.register(async (error) => {
      this.sendEvent(await this.connectivity.getNetworkType())
    })

    //订阅网络可用事件。
    Connectivity.netConnection.on('netAvailable', async (data) => {
      this.sendEvent(await this.connectivity.getNetworkType())
    })

    //订阅网络能力变化事件。
    Connectivity.netConnection.on('netCapabilitiesChange', async (data) => {
      this.sendEvent(await this.connectivity.getNetworkType())
    })

    //订阅网络连接信息变化事件
    Connectivity.netConnection.on('netConnectionPropertiesChange', async (data) => {
      this.sendEvent(await this.connectivity.getNetworkType())
    })

    //订阅网络订阅网络丢失事件。
    Connectivity.netConnection.on('netLost', (data) => {
      const types: ArrayList<String> = new ArrayList();
      types.add(Connectivity.CONNECTIVITY_NONE);
      this.sendEvent(types)
    })

    //订阅网络不可用事件。
    Connectivity.netConnection.on('netUnavailable', (data) => {
      const types: ArrayList<String> = new ArrayList();
      types.add(Connectivity.CONNECTIVITY_NONE);
      this.sendEvent(types)
    })

  }

  onCancel(args?: Object): void {
    Connectivity.netConnection.unregister((error) => {
    })
  }

  private sendEvent(networkType: ArrayList<String>): Promise<void> {
    if (this.events != null && networkType != null) {
      this.events.success(networkType);
    }
    return new Promise((reject) => {
      reject();
    })
  }
}


