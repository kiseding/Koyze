#!/usr/bin/env bash
# 校验仓库里所有 Markdown 的**本地相对链接**指向的文件确实存在。
#
# 为什么需要这个脚本：CONTRIBUTING 曾经指向一个不存在的 CODE_OF_CONDUCT.md，
# 这类死链对贡献者很不友好，而且 review 时几乎看不出来。
#
# 为什么抽成独立文件而不是写在 workflow 里：这段逻辑被一次真实的 CI 失败
# 教育过（见下方「代码片段里的 ]( 不是链接」），只在 CI 里跑的话，本地改完
# 要等 5 分钟才知道对不对。抽出来之后 `test/docs/markdown_links_test.dart`
# 可以直接调它做回归。
#
# 用法：
#   bash .github/scripts/check_md_links.sh            # 校验仓库里所有 *.md
#   bash .github/scripts/check_md_links.sh a.md b.md  # 只校验指定文件
# 退出码 0 = 全部链接有效，1 = 有死链（具体位置打印到 stderr）。
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

fail=0

# 从一段 Markdown 文本里提取「真正的」链接目标。
#
# 三个必须注意的点，每一条都对应过一次误判：
#
# 1. 链接是相对于**所在文件**的目录，不是仓库根目录——
#    docs/adr/0001 里的 ../../workers/... 从根目录看就是错的。
#
# 2. third_party/ 是 vendored 上游代码，它的 README 引用自己的截图，
#    和本仓库无关，不该拦。
#
# 3. **代码片段里的 `](` 不是链接**。围栏代码块（``` / ~~~）和行内代码
#    （`...`）里可以出现任意字符，包括 `](`。5.1.0 发版后 CI 就红在这里：
#    CHANGELOG 里描述反调试指纹时写了 `` `['toString']()` ``，被链接提取
#    当成了指向 `['toString'](` 的链接，报「引用的文件不存在」。所以必须
#    先剥掉代码块与行内代码，再提取链接。剥离顺序不能反：先剥围栏块，
#    再剥行内代码，否则无关的 ``` 会被当成行内代码的开头，把后面吞掉。
#
# 4. **不要用 `grep -oP`（或任何 `grep -P`）**。`-P` 是 GNU 专有选项，
#    macOS 自带的是 BSD grep，遇到会直接报 `grep: invalid option -- P`
#    并以非 0 退出。这条脚本在 Quality gate（ubuntu）和 iOS/macOS 构建
#    （macos runner）里都会被跑到，用 GNU 扩展就会出现「ubuntu 绿、
#    macos 红」这种最难查的分裂。2026-11-17 的 v5.1.1 IPA 构建就是
#    这么挂的（43918730505，失败在 Run deterministic Flutter tests）。
#    提取链接改用 POSIX awk，两边行为一致。
extract_targets() {
  awk '
    # 围栏代码块：遇到 ``` 或 ~~~ 整行切换状态，块内内容全部丢弃。
    # 只按行首判断，行内的反引号交给下一步处理。
    /^[[:space:]]*(```|~~~)/ { fence = !fence; next }
    fence { next }
    # 行内代码：把成对的 `...` 抹成空串。抹成空串而不是删整行，
    # 因为同一行里代码片段之后常常还跟着真正的链接。
    { line = $0; gsub(/`[^`]*`/, "", line) }
    # 逐段提取 ](target)。用 []][(][^)]*[)] 这种字符类写法而不是
    # \]\(...\)：POSIX ERE 没有为 \] 定义语义，BSD awk 上行为不确定。
    # 匹配成功后从「( 之后」取到「) 之前」，再把已处理的前缀切掉继续找，
    # 这样一行里有多个链接也不会漏。
    {
      while (match(line, /[]][(][^)]*[)]/)) {
        print substr(line, RSTART + 2, RLENGTH - 3)
        line = substr(line, RSTART + RLENGTH)
      }
    }
  ' "$1"
}

while IFS= read -r file; do
  [ -n "$file" ] || continue
  case "$file" in
    third_party/*) continue ;;
  esac
  [ -f "$file" ] || continue

  dir="$(dirname "$file")"
  while IFS= read -r target; do
    [ -n "$target" ] || continue
    # 外链、邮件、纯锚点与空目标不必查本地文件
    case "$target" in
      http*|https*|mailto:*|\#*) continue ;;
    esac
    # 去掉锚点与查询串：docs/x.md#L10 指向的仍是 x.md
    clean="${target%%#*}"
    clean="${clean%%\?*}"
    [ -n "$clean" ] || continue
    # 站点绝对路径（/foo）是站内链接，与仓库文件系统无关
    case "$clean" in
      /*) continue ;;
    esac
    if [ ! -e "$dir/$clean" ]; then
      echo "::error file=$file::引用的文件不存在: $target" >&2
      fail=1
    fi
  done < <(extract_targets "$file")
done < <(if [ "$#" -gt 0 ]; then printf '%s\n' "$@"; else git ls-files '*.md'; fi)

exit "$fail"
