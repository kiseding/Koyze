# 两阶段：先用 Flutter SDK 编出 Web 界面，再把静态产物 + Node 音源服务
# 打进同一个轻量运行镜像。部署后浏览器访问 ip:端口 即是 Koyze 原本的界面。
#
# 构建时需要仓库根目录作为 context（见 docker-compose.yml 的 build.context）。
# 主仓库 lib/ 不会被修改：Web 差异由 scripts/build-web.sh 在临时副本里施加。

FROM node:22-bookworm-slim AS web-builder

ARG FLUTTER_VERSION=3.44.9
ENV FLUTTER_HOME=/opt/flutter \
    PATH="/opt/flutter/bin:${PATH}" \
    FLUTTER_SUPPRESS_ANALYTICS=true \
    PUB_CACHE=/opt/pub-cache

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git unzip xz-utils python3 \
    && rm -rf /var/lib/apt/lists/*

# 固定版本，与 CI 里六个平台使用的 Flutter 保持一致。
RUN curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
      -o /tmp/flutter.tar.xz \
    && tar -xJf /tmp/flutter.tar.xz -C /opt \
    && rm -f /tmp/flutter.tar.xz \
    && test -x /opt/flutter/bin/flutter \
    && git config --global --add safe.directory /opt/flutter \
    && flutter --version

WORKDIR /src
COPY . .
RUN chmod +x scripts/build-web.sh \
    && FLUTTER_BIN=/opt/flutter/bin/flutter ./scripts/build-web.sh

FROM node:22-alpine

WORKDIR /app
COPY package.json ./
COPY server ./server
COPY --from=web-builder /src/webapp/public ./public
COPY sources ./sources

RUN mkdir -p /app/sources /app/data && chown -R node:node /app
USER node

ENV PORT=8080 \
    HOST=0.0.0.0 \
    NODE_ENV=production

EXPOSE 8080
VOLUME ["/app/sources", "/app/data"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:8080/api/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "server/index.js"]
