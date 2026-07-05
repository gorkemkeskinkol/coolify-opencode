#!/usr/bin/env bash
set -euo pipefail

echo "[entrypoint] starting opencode container"

if [ -n "${SSH_PRIVATE_KEY:-}" ]; then
    echo "[entrypoint] configuring SSH key for github access"
    mkdir -p "${HOME}/.ssh"
    chmod 700 "${HOME}/.ssh"

    KEY_FILE="${HOME}/.ssh/id_ed25519"

    if [ -n "${SSH_PRIVATE_KEY_B64:-}" ]; then
        echo "[entrypoint] decoding SSH_PRIVATE_KEY_B64 -> ${KEY_FILE}"
        echo "${SSH_PRIVATE_KEY_B64}" | base64 -d > "${KEY_FILE}"
    else
        printf '%s\n' "${SSH_PRIVATE_KEY}" > "${KEY_FILE}"
    fi
    chmod 600 "${KEY_FILE}"

    if ! grep -q "github.com" "${HOME}/.ssh/known_hosts" 2>/dev/null; then
        ssh-keyscan -t rsa,ecdsa,ed25519 github.com >> "${HOME}/.ssh/known_hosts" 2>/dev/null || true
    fi
    chmod 644 "${HOME}/.ssh/known_hosts"

    eval "$(ssh-agent -s)" >/dev/null
    if ! ssh-add "${KEY_FILE}"; then
        echo "[entrypoint] FATAL: ssh-add failed; first/last 200 bytes of key file:" >&2
        head -c 200 "${KEY_FILE}" >&2; echo >&2
        echo "---" >&2
        tail -c 200 "${KEY_FILE}" >&2; echo >&2
        exit 1
    fi

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
