# Build context: agent-runtime/. Callback artifact is supplied as a named context.
FROM node:22.23.2-bookworm-slim AS runtime
ARG TARGETARCH
ARG HERMES_REF=v2026.9.24
ARG GROK_BUILD_VERSION=1.0.46
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
# AgentsView is retained only for local aggregate usage reporting. Provenance
# and SPDX are checksum-verified and retained with the image for operators.
RUN curl -fsSL https://github.com/kenn-io/agentsview/releases/download/v0.44.0/agentsview_0.44.0_linux_amd64.tar.gz -o /tmp/agentsview.tar.gz \
 && echo '037ea7a46d52e06b20363b4aa7cd7f28e32f31d8215803d6e9a0c96bac5818e3  /tmp/agentsview.tar.gz' | sha256sum -c - \
 && curl -fsSL https://github.com/kenn-io/agentsview/releases/download/v0.44.0/agentsview_0.44.0_linux_amd64.tar.gz.provenance.json -o /opt/runtime/agentsview.provenance.json \
 && echo '80e6e67f61345e1fb509889a62aa3c050dec3330858475c50b03c23b170f51e3  /opt/runtime/agentsview.provenance.json' | sha256sum -c - \
 && curl -fsSL https://github.com/kenn-io/agentsview/releases/download/v0.44.0/agentsview_0.44.0_linux_amd64.tar.gz.spdx.json -o /opt/runtime/agentsview.spdx.json \
 && echo '6b31b09e5c85f70d4578b5ba46b6c1058193d90562c22336f571b3e53d43b6a7  /opt/runtime/agentsview.spdx.json' | sha256sum -c - \
 && tar -xzf /tmp/agentsview.tar.gz -C /usr/local/bin agentsview \
 && chmod 755 /usr/local/bin/agentsview \
 && rm /tmp/agentsview.tar.gz
# xAI publishes Grok Build through stable/alpha/enterprise channels, not a
# documented minor-line artifact URL. Install the current stable build chosen
# for this image; advancing it is an explicit Runtime rebuild.
RUN curl -fsSL "https://x.ai/cli/grok-${GROK_BUILD_VERSION}-linux-x86_64" -o /usr/local/bin/grok \
 && echo '41626a53292324140b92556b9d42ff5542e3dcd04aff85eafb8689dd4adb44fc  /usr/local/bin/grok' | sha256sum -c - \
 && chmod 755 /usr/local/bin/grok
# Hermes publishes dated stable release tags, not minor-line tags. The current
# installer targets newer source trees than v2026.9.24, so install this
# selected stable source release with its own frozen uv lockfile. A later
# Runtime rebuild may advance this argument to the next stable release.
RUN curl -fsSL https://github.com/astral-sh/uv/releases/download/0.12.3/uv-x86_64-unknown-linux-gnu.tar.gz -o /tmp/uv.tar.gz \
 && echo '600cf9a742aca00d292673b16b5acffaa7b8c269a364ad0c2e79498dcb1fe101  /tmp/uv.tar.gz' | sha256sum -c - \
 && tar -xzf /tmp/uv.tar.gz -C /tmp \
 && install -m 755 /tmp/uv-x86_64-unknown-linux-gnu/uv /usr/local/bin/uv \
 && rm -rf /tmp/uv.tar.gz /tmp/uv-x86_64-unknown-linux-gnu
RUN curl -fsSL --retry 4 --retry-delay 2 --retry-max-time 60 "https://github.com/NousResearch/hermes-agent/archive/refs/tags/${HERMES_REF}.tar.gz" -o /tmp/hermes-agent.tar.gz \
 && mkdir /opt/hermes-agent \
 && tar -xzf /tmp/hermes-agent.tar.gz --strip-components=1 -C /opt/hermes-agent \
 && cd /opt/hermes-agent \
 && UV_CACHE_DIR=/opt/hermes-uv-cache UV_PYTHON_INSTALL_DIR=/opt/hermes-python uv sync --frozen --no-dev --python 3.13 \
 && ln -s /opt/hermes-agent/.venv/bin/hermes /usr/local/bin/hermes \
 && chmod -R a+rX /opt/hermes-agent /opt/hermes-uv-cache /opt/hermes-python \
 && rm -f /tmp/hermes-agent.tar.gz
# Wagglebot 0.3.4 publishes the staged, self-contained package tarball. Extract
# the checksum-verified package and resolve its bundled runtime dependencies.
RUN curl -fsSL https://registry.npmjs.org/wagglebot/-/wagglebot-0.3.4.tgz -o /tmp/wagglebot.tgz \
 && echo 'd7d9d34067f19cf9cff42ac9ea4a2bbdfd4cbd08479f512776311d6857c6f2d1  /tmp/wagglebot.tgz' | sha256sum -c - \
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
 HERMES_HOME=/workspace/commander/.hermes \
 HERDR_SOCKET_PATH=/run/herdr/herdr.sock PYTHONDONTWRITEBYTECODE=1 \
 AGENTSVIEW_DATA_DIR=/home/runtime/.agentsview RUNTIME_USAGE_TIMEZONE=UTC \
 AGENTSVIEW_ARCHIVE_CONTENT=usage \
 CLAUDE_PROJECTS_DIR=/home/runtime/.claude/projects \
 CODEX_SESSIONS_DIR=/home/runtime/.codex/sessions \
 GEMINI_DIR=/home/runtime/.gemini \
 OPENCODE_DIR=/home/runtime/.local/share/opencode \
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
RUN echo "889248ea9a0f4d19dd6cfee3a54aceaee9e02ca7b566c42c160d2ad80bef47e9  /usr/local/bin/digitaltwin" | sha256sum -c -
COPY --from=kirei-clients --chmod=755 /digitaltwin-mcp /usr/local/bin/digitaltwin-mcp
RUN echo "8eaa6aadf579a75d66886e21a91ceef6843cd96604d9cc8e5886337b87dcd037  /usr/local/bin/digitaltwin-mcp" | sha256sum -c -
COPY --from=kirei-clients --chmod=755 /mcp.rb /usr/local/bin/mcp.rb
RUN echo "e4cfea5ff6390c684873093d5c79920a840e458abffd47d9cbef21593e19bd5c  /usr/local/bin/mcp.rb" | sha256sum -c -
COPY --from=kirei-clients --chmod=755 /http_tools.rb /usr/local/bin/http_tools.rb
RUN echo "633326e1207c318a58c236b5117cd4bae6318f44c409f9e697113b361d6be83d  /usr/local/bin/http_tools.rb" | sha256sum -c -
COPY --from=kirei-clients --chmod=755 /agentsview_usage_response.rb /usr/local/bin/agentsview_usage_response.rb
RUN echo "f3c65b279d3a0fc2843372ae18d0e440343d57b22ef3cc017bbb688b543bfe1d  /usr/local/bin/agentsview_usage_response.rb" | sha256sum -c -
COPY --from=kirei-clients --chmod=755 /agentsview_usage_authorizer.rb /usr/local/bin/agentsview_usage_authorizer.rb
RUN echo "2afcb2aaf7b72d0ae1db69179d396d2afff21b7144e633a56169f1bf28d955c4  /usr/local/bin/agentsview_usage_authorizer.rb" | sha256sum -c -
COPY --from=kirei-clients --chmod=755 /agentsview_usage_command.rb /usr/local/bin/agentsview_usage_command.rb
RUN echo "1997715edf644dac72b409e9fa504ddaea542f90e20d90027fde16158a62bb11  /usr/local/bin/agentsview_usage_command.rb" | sha256sum -c -
COPY --from=kirei-clients --chmod=755 /agentsview_usage_server.rb /usr/local/bin/agentsview_usage_server.rb
RUN echo "c1e9379f7f0116941f3e74819bddab3684194c9d0154b0f6a96e8e01c0f74556  /usr/local/bin/agentsview_usage_server.rb" | sha256sum -c -

# Default image explicitly leaves gated callbacks/MCP unavailable.
FROM runtime AS offline
