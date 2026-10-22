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

import connection from '@ohos.net.connection'
import { ArrayList } from '@kit.ArkTS';

const TAG = "Connectivity";

export class Connectivity {
  public static CONNECTIVITY_NONE = "none";
  private static CONNECTIVITY_WIFI = "wifi";
  private static CONNECTIVITY_MOBILE = "mobile";
  private static CONNECTIVITY_ETHERNET = "ethernet";
  private static CONNECTIVITY_BLUETOOTH = "bluetooth";
  private static CONNECTIVITY_VPN = "vpn";
  public static netConnection = connection.createNetConnection();

  constructor() {

  }

  async getNetworkType(): Promise<ArrayList<String>> {
    //通过异步方式获取网络信息
    const netHandle = await connection.getDefaultNet();
    if (netHandle.netId == 0) {
      const types: ArrayList<String> = new ArrayList();
      types.add(Connectivity.CONNECTIVITY_NONE);
      return types;
    }
    const capabilities = await connection.getNetCapabilities(netHandle);
    return this.hasTransport(capabilities.bearerTypes);
  }

  hasTransport(capabilities: Array<number>): ArrayList<String> {
    const types: ArrayList<String> = new ArrayList();
    //若数组为空返回CONNECTIVITY_NONE
    if (capabilities.length == 0) {
      types.add(Connectivity.CONNECTIVITY_NONE);
      return types;
    }
    if (capabilities.includes(connection.NetBearType.BEARER_WIFI)) {
      types.add(Connectivity.CONNECTIVITY_WIFI);
      return types;
    }
    if (capabilities.includes(connection.NetBearType.BEARER_ETHERNET)) {
      types.add(Connectivity.CONNECTIVITY_ETHERNET);
      return types;
    }
    if (capabilities.includes(connection.NetBearType.BEARER_CELLULAR)) {
      types.add(Connectivity.CONNECTIVITY_MOBILE);
      return types;
    }
    types.add(Connectivity.CONNECTIVITY_NONE);
    return types;
  }
}



