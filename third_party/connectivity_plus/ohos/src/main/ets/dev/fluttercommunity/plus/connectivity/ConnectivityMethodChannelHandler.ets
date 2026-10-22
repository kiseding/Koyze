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
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import { MethodCallHandler, MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import { Connectivity } from './Connectivity';
import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';
import { ArrayList } from '@kit.ArkTS';


const TAG: string = "ConnectivityMethodChannelHandler";

export default class ConnectivityMethodChannelHandler implements MethodCallHandler {
  private connectivity: Connectivity;

  constructor(connectivity: Connectivity) {
    this.connectivity = connectivity;
  }


  onMethodCall(call: MethodCall, result: MethodResult): void {
    Log.d(TAG, 'onMethodCall step in')
    switch (call.method) {
      case "check":
        this.handleCheckResult(result);
        break;
      default:
        result.notImplemented();
        break;
    }
  }

  async handleCheckResult(result: MethodResult): Promise<void> {
    const networkType: ArrayList<String> = await this.connectivity.getNetworkType()
    result.success(networkType)
  }
}

