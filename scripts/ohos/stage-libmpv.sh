#!/usr/bin/env bash
# 把预编译的 libmpv 放进 ohos/entry/libs/<abi>/。
#
# 为什么需要这一步：`ohos/entry/libs` 是**构建输出目录**——`flutter build hap`
# 会往里面写 libapp.so / libflutter.so，CI 为了切换架构还会先 `rm -rf` 整个目录。
# 预编译库因此存在 third_party/ohos-libmpv/，由本脚本在构建前拷进去。
#
# libc++_shared.so 必须与 libmpv.so **同目录**：它不在应用 linker namespace 里，
# 只放 libmpv.so 会在 dlopen 时报找不到符号。
#
# 用法：
#   scripts/ohos/stage-libmpv.sh            # 所有已提供的 ABI
#   scripts/ohos/stage-libmpv.sh arm64-v8a  # 只拷指定 ABI
#
# 没有预编译库的 ABI 会被跳过而不是报错，但**该 ABI 的包装上去是起不来的**：
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
  echo "stage-libmpv: $src 下没有任何 ABI 目录，跳过"
  exit 0
fi

staged=0
for abi in "${abis[@]}"; do
  if [ ! -d "$src/$abi" ]; then
    echo "stage-libmpv: 跳过 $abi（$src/$abi 不存在）"
    continue
  fi
  mkdir -p "$dst/$abi"
  cp -f "$src/$abi"/*.so "$dst/$abi"/
  echo "stage-libmpv: $abi <- $(cd "$src/$abi" && ls ./*.so | tr '\n' ' ')"
  staged=$((staged + 1))
done

if [ "$staged" -eq 0 ]; then
  echo "stage-libmpv: 一个 ABI 都没拷到"
fi
