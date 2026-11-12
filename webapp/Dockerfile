# 两阶段：先用 Flutter SDK 编出 Web 界面，再把静态产物 + Node 音源服务
# 打进同一个轻量运行镜像。部署后浏览器访问 ip:端口 即是 Koyze 原本的界面。
#
# 构建时需要仓库根目录作为 context（见 docker-compose.yml 的 build.context）。
# 主仓库 lib/ 不会被修改：Web 差异由 scripts/build-web.sh 在临时副本里施加。

FROM node:22-bookworm-slim AS web-builder

ARG FLUTTER_VERSION=3.44.9
# Flutter SDK 与 pub 包的下载源。国内网络下官方 storage.googleapis.com 与
# pub.dev 都可能极慢甚至超时，构建时换镜像即可：
#   docker compose build --build-arg FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
ARG FLUTTER_STORAGE_BASE_URL=https://storage.googleapis.com
ARG PUB_HOSTED_URL=https://pub.dev

ENV FLUTTER_HOME=/opt/flutter \
    PATH="/opt/flutter/bin:${PATH}" \
    FLUTTER_SUPPRESS_ANALYTICS=true \
    PUB_CACHE=/opt/pub-cache \
    FLUTTER_STORAGE_BASE_URL=${FLUTTER_STORAGE_BASE_URL} \
    PUB_HOSTED_URL=${PUB_HOSTED_URL}

# python3 是 scripts/build-web.sh 里补丁脚本的解释器；python3-pil 是
# scripts/web-patch/make_web_icons.py 的硬依赖——缺了它脚本会打印
# "error: Pillow is required" 并以 1 退出，配合 set -e 直接中断构建。
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git unzip xz-utils python3 python3-pil \
    && rm -rf /var/lib/apt/lists/*

# 固定版本，与 CI 里六个平台使用的 Flutter 保持一致。
RUN curl -fsSL "${FLUTTER_STORAGE_BASE_URL}/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
      -o /tmp/flutter.tar.xz \
    && tar -xJf /tmp/flutter.tar.xz -C /opt \
    && rm -f /tmp/flutter.tar.xz \
    && test -x /opt/flutter/bin/flutter \
    && git config --global --add safe.directory /opt/flutter \
    && flutter --version

WORKDIR /src
COPY . .
# 只拷源码，不拷宿主的构建缓存：context 里可能带着 Windows/macOS 的
# build/ 与 .dart_tool/，直接复用会在 Linux 上解析出错误路径。
#
# 另外必须先把脚本的 CRLF 洗成 LF。`.gitattributes` 只保证仓库里是 LF，
# 但 build context 取的是**工作区**，Windows 上检出后就是 CRLF。Linux 内核
# 会把这行 shebang 原样交给 /usr/bin/env，env 于是去找一个名叫 "bash\r" 的
# 程序，报 `No such file or directory`；Git Bash 自带 CRLF 兼容所以本地跑没事。
RUN find scripts -type f \( -name '*.sh' -o -name '*.py' \) -exec sed -i 's/\r$//' {} + \
    && rm -rf build .dart_tool \
    && chmod +x scripts/build-web.sh \
    && FLUTTER_BIN=/opt/flutter/bin/flutter ./scripts/build-web.sh

FROM node:22-alpine

WORKDIR /app
# 注意：build context 是**仓库根目录**（见 docker-compose.yml），所以这里的
# 源路径必须带 `webapp/` 前缀。写成 `COPY package.json ./` 会去找仓库根下的
# package.json——那个文件不存在，构建会直接失败。
#
# 用 --chown 而不是后面再 `chown -R /app`：后者会把 50 MB 的 public 目录
# 在新层里整份复制一遍，镜像白胖 50 MB。
COPY --chown=node:node webapp/package.json ./
COPY --chown=node:node webapp/server ./server
COPY --chown=node:node --from=web-builder /src/webapp/public ./public
COPY --chown=node:node webapp/sources ./sources

# 两个卷的挂载点在镜像里先建好并交给 node：/app/data 要写用户导入的音源。
RUN mkdir -p /app/sources /app/data && chown node:node /app/sources /app/data
USER node

ENV PORT=8080 \
    HOST=0.0.0.0 \
    NODE_ENV=production

EXPOSE 8080
VOLUME ["/app/sources", "/app/data"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD node -e "const p=process.env.PORT||8080;fetch('http://127.0.0.1:'+p+'/api/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "server/index.js"]
