FROM node:22-slim

ARG OPENCODE_VERSION=1.17.13

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    openssh-client \
    ca-certificates \
    curl \
    bash \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://opencode.ai/install | bash -s -- --version ${OPENCODE_VERSION} --no-modify-path \
    && ln -sf /root/.opencode/bin/opencode /usr/local/bin/opencode

WORKDIR /projects

COPY opencode.jsonc /opt/opencode-seed/opencode.jsonc
COPY AGENTS.md      /opt/opencode-seed/AGENTS.md
COPY entrypoint.sh  /entrypoint.sh
RUN chmod +x /entrypoint.sh

VOLUME ["/projects", "/opencode"]

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD PORT=$(cat /root/.opencode_port 2>/dev/null || echo 3000); \
        curl -fsS "http://127.0.0.1:${PORT}/global/health" || exit 1

ENTRYPOINT ["/entrypoint.sh"]
