# Build context: agent-runtime/. Callback artifact is supplied as a named context.
FROM node:22.23.2-bookworm-slim AS runtime
ARG TARGETARCH
RUN test "$TARGETARCH" = amd64
COPY apt-packages.lock /opt/runtime/apt-packages.lock
RUN apt-get update \
 && xargs -r apt-get install -y --no-install-recommends < /opt/runtime/apt-packages.lock \
 && rm -rf /var/lib/apt/lists/*
# Callback MCP sources are strict Sorbet Ruby and run standalone in this image.
# Download the exact runtime gem, verify it before installation, then install
# locally so the build never trusts an unverified registry response.
RUN curl -fsSL https://rubygems.org/downloads/sorbet-runtime-0.6.13517.gem -o /tmp/sorbet-runtime.gem \
 && echo 'a36469f5b45c3493721ff62fb1ff27186b7c228fe70894464f680056c66e8cf8  /tmp/sorbet-runtime.gem' | sha256sum -c - \
 && gem install --local --no-document /tmp/sorbet-runtime.gem \
 && rm /tmp/sorbet-runtime.gem
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
RUN groupadd --gid 10001 runtime && useradd --uid 10001 --gid 10001 --create-home --shell /bin/bash runtime \
 && mkdir -p /workspace/repos /workspace/worktrees /run/herdr /home/runtime/.cache /home/runtime/.local/share \
 && ln -s /usr/bin/fdfind /usr/local/bin/fd \
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
 && dpkg-query --show --showformat='${binary:Package}=${Version}\n' | sort > /opt/runtime/installed-apt.txt
USER 10001:10001
WORKDIR /home/runtime
VOLUME ["/home/runtime", "/workspace", "/run/herdr"]
HEALTHCHECK --interval=10s --timeout=5s --start-period=20s --retries=3 CMD ["/opt/runtime/bin/runtime-health"]
ENTRYPOINT ["/usr/bin/tini", "--", "/opt/runtime/entrypoint.sh"]
CMD ["herdr", "server"]

# Only use after the backend owner publishes its standalone stdlib client.
# docker build --target with-callback --build-context kirei-clients=<artifact-dir>
FROM runtime AS with-callback
COPY --from=kirei-clients --chmod=755 /digitaltwin /usr/local/bin/digitaltwin
RUN echo "6062994ea169e8d9f2137063e3b61113baa22709766efe381dc2587d5ae55a95  /usr/local/bin/digitaltwin" | sha256sum -c -
COPY --from=kirei-clients --chmod=755 /digitaltwin-mcp /usr/local/bin/digitaltwin-mcp
RUN echo "6408102ae1a9ee3a76a4606007c6b8609f9d9154ba0cebb459d7a0542c4d0ea7  /usr/local/bin/digitaltwin-mcp" | sha256sum -c -
COPY --from=kirei-clients --chmod=755 /mcp.rb /usr/local/bin/mcp.rb
RUN echo "e4cfea5ff6390c684873093d5c79920a840e458abffd47d9cbef21593e19bd5c  /usr/local/bin/mcp.rb" | sha256sum -c -
COPY --from=kirei-clients --chmod=755 /http_tools.rb /usr/local/bin/http_tools.rb
RUN echo "cecbe55e68ad4535266ed1d7718fb7c485a5eb600d2ef4ed7fc8c740db66f0e4  /usr/local/bin/http_tools.rb" | sha256sum -c -

# Default image explicitly leaves gated callbacks/MCP unavailable.
FROM runtime AS offline
