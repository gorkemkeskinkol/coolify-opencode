#!/usr/bin/env bash
set -euo pipefail

echo "[entrypoint] starting opencode container"

if [ -n "${SSH_PRIVATE_KEY:-}" ]; then
    echo "[entrypoint] configuring SSH key for github access"
    mkdir -p "${HOME}/.ssh"
    chmod 700 "${HOME}/.ssh"

    printf '%s\n' "${SSH_PRIVATE_KEY}" > "${HOME}/.ssh/id_ed25519"
    chmod 600 "${HOME}/.ssh/id_ed25519"

    if ! grep -q "github.com" "${HOME}/.ssh/known_hosts" 2>/dev/null; then
        ssh-keyscan -t rsa,ecdsa,ed25519 github.com >> "${HOME}/.ssh/known_hosts" 2>/dev/null || true
    fi
    chmod 644 "${HOME}/.ssh/known_hosts"

    eval "$(ssh-agent -s)" >/dev/null
    ssh-add "${HOME}/.ssh/id_ed25519"

    cat > "${HOME}/.gitconfig" <<EOF
[user]
    name = ${GIT_USER_NAME:-opencode}
    email = ${GIT_USER_EMAIL:-opencode@localhost}
[core]
    sshCommand = ssh -o StrictHostKeyChecking=accept-new
EOF

    echo "[entrypoint] SSH agent ready, key loaded"
else
    echo "[entrypoint] SSH_PRIVATE_KEY not provided, skipping ssh-agent setup"
fi

PORT="${PORT:-3000}"
echo "[entrypoint] starting opencode serve on 0.0.0.0:${PORT}"

exec opencode serve --hostname 0.0.0.0 --port "${PORT}"
