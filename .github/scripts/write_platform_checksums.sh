#!/usr/bin/env bash
# 为某个平台的构建产物生成 SHA256SUMS.<平台>.txt。
#
# 用法：write_platform_checksums.sh <产物目录> <平台标识>
# 例：  write_platform_checksums.sh build/macos macos
#
# 输出（覆盖写）：<产物目录>/SHA256SUMS.<平台>.txt
#
# ## 为什么每个平台各写一份，而不是各自发一份 SHA256SUMS.txt
#
# 7 个平台 workflow 是并行触发、并行上传到同一个 Release 的。如果每个都
# 生成完整的 `SHA256SUMS.txt`，谁最后上传谁赢，先到的那份被覆盖——结果是
# 一份看起来正常、实际只覆盖部分产物的校验文件，比没有更危险。
#
# 5.1.1 发版时就是这种情况：只有鸿蒙 workflow 生成 SHA256SUMS.txt，于是
# Release 里那份文件只有两个 .hap 的哈希，Android/桌面/iOS 的 7 个产物
# 一个都没覆盖，而且写的是构建机上的相对路径（build/harmonyos-release/...），
# 用户下载后无从校验。所以改成：
#   各平台 → SHA256SUMS.<platform>.txt（带平台后缀，互不覆盖）
#   汇总   → release-checksums.yml 取齐所有后缀，拼成唯一的 SHA256SUMS.txt
#
# ## 为什么用 `*file` 而不是 ` file`
#
# GNU coreutils 的 sha256sum 和 macOS 的 shasum 输出格式都是
# `<hex>  <name>`（两个空格，文本模式）。带 `*` 前缀表示二进制模式：
# 语义更准确（这些是二进制包），且 GNU/BSD 的 `-c` 都认这个格式。
#
# 路径只写文件名、不写构建机目录。这样用户把产物和 SHA256SUMS.txt 放在
# 同一个目录里，`sha256sum -c SHA256SUMS.txt` 就能直接跑通。
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <artifact-dir> <platform>" >&2
  exit 2
fi

dir="$1"
platform="$2"
out="$dir/SHA256SUMS.$platform.txt"

if [ ! -d "$dir" ]; then
  echo "artifact dir not found: $dir" >&2
  exit 1
fi

# 平台标识只允许小写字母、数字和连字符，避免拼出奇怪的文件名。
#
# 这里刻意**不用** `case` 的字符区间（原来写的是 `*[!a-z-]*`）：bash 3.2
# 解析括号表达式时，会把结尾的 `-` 当成区间起点，于是 `-`(0x2D) 到
# `]`(0x5D) 之间整段 ASCII 都被算作「合法字符」，大写字母正好落在里面。
# macOS runner 用的就是 3.2（/bin/bash），这条校验在那里退化成「什么都
# 接受」——5.2.0 的 iOS 发版就是被它卡住的：`平台标识不合法时拒绝执行`
# 期望非 0、实际拿到 0。而开发机上的 bash 4/5 会正确拒绝，本地永远复现
# 不出来。
#
# 改成 LC_ALL=C + 显式白名单的正则：既不吃 bash 括号解析的亏，也不受
# 排序规则影响（C locale 下 `[a-z]` 就是 0x61-0x7A 这 26 个字节）。
if ! LC_ALL=C grep -Eq '^[a-z0-9]+(-[a-z0-9]+)*$' <<< "$platform"; then
  echo "invalid platform tag: $platform" >&2
  exit 2
fi

# 先写到临时文件，全部成功后再改名成正式的分片。
#
# 不能像最初那样直接 `: > "$out"` 然后边算边追加：万一中途失败（没有产物、
# 哈希工具缺失），产物目录里会留一个**空的** SHA256SUMS.<平台>.txt。这个空
# 文件会被上传到 Release、被汇总 workflow 当成「该平台已完成」而对上，
# 于是整个平台的产物静默缺席——正是要防的那类失败，只是更难发现。
#
# 临时文件带 PID 后缀，避免同一台上并行调用时互相踩。
tmp="$out.tmp.$$"
: > "$tmp"
# 失败退出时清掉临时文件。
#
# 注意这里刻意用 `exec 3>&-` + `rm -f ... || true` 而不是裸 rm：
# 某些环境（例如开发机上的 safe-delete 包装）会拒绝删除含盘符的路径，
# rm 返回非 0。trap 里的失败不该再改变退出码，所以吞掉。
# CI runner 上没有这种包装，rm 会正常删掉。
trap 'rm -f "$tmp" 2>/dev/null || true' EXIT

# 遍历顺序固定（sort），同一组产物每次生成的哈希行顺序一致，
# 汇总出来的 SHA256SUMS.txt 才可能逐字节稳定。
#
# 这里**不能**换成 `find -print0 | sort -z` 来免疫「文件名含换行」：
# macOS runner 上是 BSD sort，不保证支持 -z（也没装 coreutils），
# 换上就等于把 macOS 发版做挂了。收益（产物名带换行）在现实中不存在，
# 而代价是整个平台的发版失败，不划算。真要带换行，脚本会红并报出
# 「No such file or directory」——是失败而不是错数据，可以接受。
#
# ## 为什么只算 `Koyze-*`
#
# 分片是给用户校验**下载到手的产物**用的，里面每一条都必须对应 Release 上
# 一个真实存在的文件。而产物目录往往不是干净的：`flutter build` 会在同层
# 留下 `pod_inputs.fingerprint`、`framework_public_headers.fingerprint`、
# `info.plist`、`app.so` 这类中间文件。5.2.0 的第一次汇总就是这么红的——
# macOS / iOS / Windows 的分片里各混进几条，汇总拿分片去 `sha256sum -c`，
# 那些名字在 Release 上当然不存在，于是整份校验和发布不出去。
#
# 所有平台的产物都以 `Koyze-` 开头，所以这里用正向白名单，而不是「排除掉
# 已知的几种垃圾」——后者永远追不上构建工具下次写出来的新文件名。
# 漏算的后果也不是静默的：汇总 workflow 有反向覆盖检查（Release 上的每个
# 产物都必须在分片里出现），漏了会直接红。
pattern="${ARTIFACT_PATTERN:-Koyze-*}"
found=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  name="$(basename "$f")"
  # 跳过自己以及可能残留的旧汇总文件（有白名单后已不可能命中，留作双保险）
  case "$name" in
    SHA256SUMS*|*.sha256) continue ;;
  esac
  case "$f" in
    *.txt|*.md|*.json) continue ;;
  esac
  found=1
  # sha256sum 与 shasum 的参数一致（-a 256 是 shasum 专用，这里统一走
  # sha256sum 存在性探测；macOS runner 上装了 coreutils 也有 sha256sum，
  # 但 Git Bash / 精简镜像可能只有 shasum，所以两条路都要留）
  if command -v sha256sum >/dev/null 2>&1; then
    hash="$(sha256sum "$f" | awk '{print $1}')"
  elif command -v shasum >/dev/null 2>&1; then
    hash="$(shasum -a 256 "$f" | awk '{print $1}')"
  else
    echo "neither sha256sum nor shasum available" >&2
    exit 1
  fi
  echo "$hash *$name" >> "$tmp"
done < <(find "$dir" -maxdepth 1 -type f -name "$pattern" | sort)

if [ "$found" -eq 0 ]; then
  # 这里不能只依赖 rm：某些环境（如本机的 safe-delete 钩子）会拒绝删除
  # 含盘符路径，rm 静默失败后文件就留下了。既然我们从未写到 $out，
  # 这里根本不需要删它——直接退出即可。
  echo "no artifact found in $dir" >&2
  exit 1
fi

# 排序保证跨机器稳定（find | sort 已排过一次，这里再按文件名列排一次，
# 防止 find 输出受文件系统顺序影响）
sort -k2 "$tmp" -o "$tmp"

# 原子改名：到这一步才让正式分片出现，前面任何失败都不会留下残缺文件
mv "$tmp" "$out"

cat "$out"
