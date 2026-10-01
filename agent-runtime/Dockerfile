# Build context: agent-runtime/. Callback artifact is supplied as a named context.
FROM node:22.23.2-alpine3.23@sha256:72c5815a06aed9a2273aea5628d74d348af57843a7b547af2fe53dd3e4b95261 AS runtime
ARG TARGETARCH
RUN test "$TARGETARCH" = amd64
COPY apk-packages.lock /opt/runtime/apk-packages.lock
RUN xargs apk add --no-cache < /opt/runtime/apk-packages.lock
WORKDIR /opt/runtime
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --no-audit --no-fund && npm cache clean --force
RUN curl -fsSL https://github.com/herdrdev/herdr/releases/download/v0.9.3/herdr-linux-x86_64 -o /usr/local/bin/herdr \
 && echo '18a8dc65f1c2fa485884344356dea1cfd911c6f06cf46fa78e193f4087f4dba7  /usr/local/bin/herdr' | sha256sum -c - \
 && chmod 755 /usr/local/bin/herdr
# 0.3.0's published workspace:* dependencies break npm installation. Its dist is
# standalone; retain the package unmodified and resolve skills through NODE_PATH.
RUN curl -fsSL https://registry.npmjs.org/wagglebot/-/wagglebot-0.3.0.tgz -o /tmp/wagglebot.tgz \
 && echo 'b9adcf0d854b6a7ed338463329e5ec0062adb79c3cbb9189fdf14fffb4b51974  /tmp/wagglebot.tgz' | sha256sum -c - \
 && mkdir /opt/wagglebot && tar -xzf /tmp/wagglebot.tgz --strip-components=1 -C /opt/wagglebot \
 && chmod 755 /opt/wagglebot/bin/wagglebot.js \
 && ln -s /opt/wagglebot/bin/wagglebot.js /usr/local/bin/wagglebot && rm /tmp/wagglebot.tgz
RUN addgroup -g 10001 runtime && adduser -D -u 10001 -G runtime -s /bin/bash runtime \
 && mkdir -p /workspace/repos /workspace/worktrees /run/herdr /home/runtime/.cache /home/runtime/.local/share \
 && chown -R 10001:10001 /workspace /run/herdr /home/runtime
ENV HOME=/home/runtime SHELL=/bin/bash \
 PATH=/opt/runtime/bin:/opt/runtime/node_modules/.bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
 NODE_PATH=/opt/runtime/node_modules \
 HERDR_SOCKET_PATH=/run/herdr/herdr.sock PYTHONDONTWRITEBYTECODE=1 \
 USE_BUILTIN_RIPGREP=0
COPY contracts /opt/runtime/contracts
COPY config /opt/runtime/config
COPY config/runtime-shell.sh /etc/profile.d/runtime.sh
COPY bin /opt/runtime/bin
COPY entrypoint.sh /opt/runtime/entrypoint.sh
RUN chmod 755 /opt/runtime/entrypoint.sh /opt/runtime/bin/* \
 && apk info -v | sort > /opt/runtime/installed-apk.txt
USER 10001:10001
WORKDIR /home/runtime
VOLUME ["/home/runtime", "/workspace", "/run/herdr"]
HEALTHCHECK --interval=10s --timeout=5s --start-period=20s --retries=3 CMD ["/opt/runtime/bin/runtime-health"]
ENTRYPOINT ["/sbin/tini", "--", "/opt/runtime/entrypoint.sh"]
CMD ["herdr", "server"]

# Only use after the backend owner publishes its standalone stdlib client.
# docker build --target with-callback --build-context kirei-clients=<artifact-dir>
FROM runtime AS with-callback
COPY --from=kirei-clients --chmod=755 /digitaltwin /usr/local/bin/digitaltwin
RUN echo "cd7dd6f80e050b91387c92fa285964f19ed089bb84b44c8dbb0dd5caf8478054  /usr/local/bin/digitaltwin" | sha256sum -c -

# Default image explicitly leaves gated callbacks/MCP unavailable.
FROM runtime AS offline
