#!/usr/bin/env bash
# 用 hap-sign-tool 给 Koyze 的 HAP 签名（发布证书 / 无设备限制）
#
# 用法：
#   ./sign-hap.sh <unsigned.hap> [out-signed.hap]
#
# 材料（默认在 ./signing/，可用 SIGN_DIR 覆盖）：
#   koyze.p12            私钥库（alias=koyze，ECC P-256）
#   koyze-release.cer    AGC 下载的发布证书链（PEM，含 3 张：根CA/中间CA/你的证书）
#   Koyze-release.p7b    AGC 下载的发布 Profile
#
# 密码来源（按顺序取第一个非空的）：
#   1. 环境变量 KEY_PWD / STORE_PWD
#   2. $SIGN_DIR/password.txt 的第一行（本地用，务必加入 .gitignore）
#
# 校验：签完自动 verify-app，不通过则非零退出

set -euo pipefail

IN=${1:?用法: ./sign-hap.sh <unsigned.hap> [out-signed.hap]}
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIGN_DIR=${SIGN_DIR:-$HERE/signing}
CLT_HOME=${CLT_HOME:-/d/fo/command-line-tools}
KEY_ALIAS=${KEY_ALIAS:-koyze}

OUT=${2:-${IN%-unsigned.hap}-signed.hap}
[ "$OUT" = "$IN" ] && OUT="${IN%.hap}-signed.hap"

TOOL="$CLT_HOME/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar"
[ -f "$TOOL" ] || { echo "找不到 $TOOL"; exit 1; }
command -v java >/dev/null 2>&1 || { echo "找不到 java（需要 JDK 17+）"; exit 1; }

STORE_FILE="$SIGN_DIR/koyze.p12"
CERT_FILE="$SIGN_DIR/koyze-release.cer"
PROFILE_FILE="$SIGN_DIR/Koyze-release.p7b"
for f in "$STORE_FILE" "$CERT_FILE" "$PROFILE_FILE" "$IN"; do
  [ -f "$f" ] || { echo "缺少文件: $f"; exit 1; }
done

if [ -z "${KEY_PWD:-}" ] || [ -z "${STORE_PWD:-}" ]; then
  if [ -f "$SIGN_DIR/password.txt" ]; then
    PW="$(head -1 "$SIGN_DIR/password.txt" | tr -d '\r\n')"
    KEY_PWD=${KEY_PWD:-$PW}
    STORE_PWD=${STORE_PWD:-$PW}
  fi
fi
[ -n "${KEY_PWD:-}" ] || { echo "缺少签名密码：设置 KEY_PWD/STORE_PWD 或写 $SIGN_DIR/password.txt"; exit 1; }
[ -n "${STORE_PWD:-}" ] || STORE_PWD="$KEY_PWD"

echo "== 签名 $(basename "$IN") =="
VDIR="${TMPDIR:-/tmp}/hapverify.$$"
mkdir -p "$VDIR"
trap 'rm -rf "$VDIR"' EXIT
rm -f "$OUT"
if ! java -jar "$TOOL" sign-app \
  -keyAlias "$KEY_ALIAS" \
  -signAlg "SHA256withECDSA" \
  -mode "localSign" \
  -appCertFile "$CERT_FILE" \
  -profileFile "$PROFILE_FILE" \
  -inFile "$IN" \
  -keystoreFile "$STORE_FILE" \
  -outFile "$OUT" \
  -keyPwd "$KEY_PWD" \
  -keystorePwd "$STORE_PWD" > "$VDIR/sign.log" 2>&1; then
  cat "$VDIR/sign.log"
  echo "签名工具执行失败"
  exit 1
fi
grep -E "INFO - (Start sign-app|profile type|Sign successfully|Sign Hap success|sign-app success|error|ERROR)" "$VDIR/sign.log" || cat "$VDIR/sign.log"
[ -s "$OUT" ] || { echo "签名失败，没有产出有效文件 $OUT"; exit 1; }

echo "== 校验签名 =="
if ! java -jar "$TOOL" verify-app -inFile "$OUT" \
     -outCertChain "$VDIR/chain.cer" -outProfile "$VDIR/profile.p7b" > "$VDIR/verify.log" 2>&1; then
  cat "$VDIR/verify.log"
  echo "签名校验命令执行失败"
  exit 1
fi
if ! grep -q "Verify success" "$VDIR/verify.log"; then
  cat "$VDIR/verify.log"
  echo "签名校验失败"
  exit 1
fi
echo "签名校验通过"

ls -lh "$OUT"
