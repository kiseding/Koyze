#!/usr/bin/env bash
# 把预编译的 libmpv 放进 ohos/entry/libs/<abi>/。
#
# 为什么需要这一步：`ohos/entry/libs` 是**构建输出目录**——`flutter build hap`
# 会往里面写 libapp.so / libflutter.so，CI 为了切换架构还会先 `rm -rf` 整个目录。
# 预编译库因此存在 third_party/ohos-libmpv/，由本脚本在构建前拷进去。
#
# libc++_shared.so 必须与 libmpv.so **同目录**，而且 libmpv.so 自己必须声明
# `DT_NEEDED libc++_shared.so`——两者缺一不可。同目录只解决「找得到文件」，
# 找得到符号还要求 libmpv 的依赖表里有它：linker 只在库自己的依赖域里解析符号，
# 光把 so 放在旁边、libmpv 又没声明依赖，dlopen 依旧报 symbol not found。
# 预编译的 libmpv 恰好漏了这条依赖（见 fix-libmpv-needed.py），拷完必须补上。
#
# 用法：
#   scripts/ohos/stage-libmpv.sh            # 所有已提供的 ABI
#   scripts/ohos/stage-libmpv.sh arm64-v8a  # 只拷指定 ABI
#
# 缺少指定 ABI 的预编译库必须中止构建：
# libmpv 是鸿蒙上唯一的播放引擎，`createMpvPlaybackEngine` 在它加载失败时
# 直接抛 `PlaybackEngineUnavailable`，应用落到启动失败页并显示具体原因。
#
# 这里不再有「退回 just_audio」这条路——均衡器、交叉馈送、限幅、实时频谱
# 全部挂在 mpv 的 `af` 滤镜链和 FFT 管线上，换成 just_audio 它们会集体失效，
# 用户看到的只是一句「均衡器不可用」。与其静默降级，不如在启动时就明确失败。
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
src="$root/third_party/ohos-libmpv"
dst="$root/ohos/entry/libs"

if [ "$#" -gt 0 ]; then
  abis=("$@")
else
  abis=()
  for dir in "$src"/*/; do
    [ -d "$dir" ] || continue
    abis+=("$(basename "$dir")")
  done
fi

if [ "${#abis[@]}" -eq 0 ]; then
  echo "stage-libmpv: $src 下没有任何 ABI 目录" >&2
  exit 1
fi

for abi in "${abis[@]}"; do
  for lib in libmpv.so libc++_shared.so; do
    if [ ! -s "$src/$abi/$lib" ]; then
      echo "stage-libmpv: 缺少 $src/$abi/$lib，拒绝构建不可启动的 HAP" >&2
      exit 1
    fi
  done
  mkdir -p "$dst/$abi"
  cp -f "$src/$abi/libmpv.so" "$src/$abi/libc++_shared.so" "$dst/$abi"/
  # 预编译库的 DT_NEEDED 里没有 libc++_shared.so，就地补上（幂等）。
  # 改的是拷到构建目录的副本，third_party 下的原始文件保持不动。
  python3 "$root/scripts/ohos/fix-libmpv-needed.py" "$dst/$abi/libmpv.so"
  echo "stage-libmpv: $abi <- libmpv.so libc++_shared.so"
done
