#!/usr/bin/env bash
set -euo pipefail

echo "[entrypoint] starting opencode container"

if [ -n "${SSH_PRIVATE_KEY:-}" ]; then
    echo "[entrypoint] configuring SSH key for github access"
    mkdir -p "${HOME}/.ssh"
    chmod 700 "${HOME}/.ssh"

    KEY_FILE="${HOME}/.ssh/id_ed25519"

    write_key() {
        local src="$1" out="$2"
        local first_line
        first_line=$(printf '%s' "$src" | head -n 1 | tr -d '\r')
        if printf '%s' "$first_line" | grep -q -- "-----BEGIN"; then
            printf '%s' "$src" > "$out"
            printf '\n' >> "$out"
        else
            if ! printf '%s' "$src" | base64 -d > "$out" 2>/tmp/base64_err; then
                echo "[entrypoint] FATAL: SSH_PRIVATE_KEY base64 decode failed:" >&2
                cat /tmp/base64_err >&2
                exit 1
            fi
        fi
        if ! head -n 1 "$out" | grep -q -- "-----BEGIN"; then
            echo "[entrypoint] FATAL: key file does not start with a PEM header" >&2
            echo "             first 200 bytes:" >&2
            head -c 200 "$out" >&2; echo >&2
            echo >&2
            echo "             SSH_PRIVATE_KEY was treated as:" >&2
            if printf '%s' "$first_line" | grep -q -- "-----BEGIN"; then
                echo "               PEM (but file does not look like PEM?)" >&2
            else
                echo "               base64 (decoded result is not PEM)" >&2
            fi
            echo "             Provide either:" >&2
            echo "               - SSH_PRIVATE_KEY_B64=\$(base64 -w0 < keyfile)" >&2
            echo "               - SSH_PRIVATE_KEY=\$(cat keyfile)   (PEM, multiline)" >&2
            exit 1
        fi
    }

    if [ -n "${SSH_PRIVATE_KEY_B64:-}" ]; then
        echo "[entrypoint] decoding SSH_PRIVATE_KEY_B64 -> ${KEY_FILE}"
        printf '%s' "${SSH_PRIVATE_KEY_B64}" | base64 -d > "${KEY_FILE}" || {
            echo "[entrypoint] FATAL: SSH_PRIVATE_KEY_B64 base64 decode failed" >&2
            exit 1
        }
    else
        write_key "${SSH_PRIVATE_KEY}" "${KEY_FILE}"
    fi
    chmod 600 "${KEY_FILE}"

    if ! grep -q "github.com" "${HOME}/.ssh/known_hosts" 2>/dev/null; then
        ssh-keyscan -t rsa,ecdsa,ed25519 github.com >> "${HOME}/.ssh/known_hosts" 2>/dev/null || true
    fi
    chmod 644 "${HOME}/.ssh/known_hosts"

    eval "$(ssh-agent -s)" >/dev/null
    if ! ssh-add "${KEY_FILE}" 2>/tmp/sshadd_err; then
        echo "[entrypoint] FATAL: ssh-add failed:" >&2
        cat /tmp/sshadd_err >&2
        echo "[entrypoint] first/last 200 bytes of key file:" >&2
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
echo "${PORT}" > "${HOME}/.opencode_port"
echo "[entrypoint] starting opencode serve on 0.0.0.0:${PORT}"

exec opencode serve --hostname 0.0.0.0 --port "${PORT}"
