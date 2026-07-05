#!/usr/bin/env bash
set -euo pipefail

echo "[entrypoint] starting opencode container"

if [ -n "${SSH_PRIVATE_KEY:-}" ]; then
    echo "[entrypoint] configuring SSH key for github access"
    mkdir -p "${HOME}/.ssh"
    chmod 700 "${HOME}/.ssh"

    KEY_FILE="${HOME}/.ssh/id_ed25519"

    # Normalize a possibly mangled PEM env value into a clean on-disk file.
    # Handles: literal "\n", stripped newlines (single-line "PEM"), CRLF,
    # missing trailing newline. Body is rebuilt at 70-char lines per OpenSSH.
    write_pem() {
        local src="$1" out="$2"
        local raw hdr ftr body
        raw=$(printf '%s' "$src" | sed 's/\\n/\
/g' | tr -d '\r')
        hdr=$(printf '%s' "$raw" | grep -oE -- '-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----' | head -1)
        ftr=$(printf '%s' "$raw" | grep -oE -- '-----END [A-Z0-9 ]*PRIVATE KEY-----' | head -1)
        if [ -z "$hdr" ] || [ -z "$ftr" ]; then
            return 1
        fi
        body=$(printf '%s' "$raw" \
            | sed -E "s/-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----//" \
            | sed -E "s/-----END [A-Z0-9 ]*PRIVATE KEY-----//" \
            | tr -d '[:space:]')
        {
            printf '%s\n' "$hdr"
            printf '%s' "$body" | fold -w 70
            printf '\n%s\n' "$ftr"
        } > "$out"
    }

    # Try PEM, then base64. Whichever yields a cryptographically valid
    # private key (verified via ssh-keygen -l) wins.
    write_key() {
        local src="$1" out="$2"
        local pem_ok=0 b64_ok=0 pem_out b64_out

        pem_out=$(mktemp); b64_out=$(mktemp)
        if write_pem "$src" "$pem_out" 2>/dev/null; then
            chmod 600 "$pem_out"
            if ssh-keygen -l -f "$pem_out" >/dev/null 2>&1; then
                pem_ok=1
            fi
        fi
        if printf '%s' "$src" | base64 -d > "$b64_out" 2>/dev/null; then
            # OpenSSH PEM parser requires a trailing newline after the
            # END marker; base64 -d does not add one. Doubling is harmless.
            printf '\n' >> "$b64_out"
            chmod 600 "$b64_out"
            if ssh-keygen -l -f "$b64_out" >/dev/null 2>&1; then
                b64_ok=1
            fi
        fi

        if [ "$pem_ok" = "1" ]; then
            echo "[entrypoint] decoded as PEM (with newline-repair if needed)" >&2
            cp "$pem_out" "$out"
        elif [ "$b64_ok" = "1" ]; then
            echo "[entrypoint] decoded as base64" >&2
            cp "$b64_out" "$out"
        else
            echo "[entrypoint] FATAL: SSH_PRIVATE_KEY is neither a valid PEM nor valid base64" >&2
            echo "             first 200 bytes of the env value:" >&2
            printf '%s' "$src" | head -c 200 >&2; echo >&2
            echo "             (PEM repair and base64 decode both failed.)" >&2
            rm -f "$pem_out" "$b64_out"
            exit 1
        fi
        rm -f "$pem_out" "$b64_out"
    }

    if [ -n "${SSH_PRIVATE_KEY_B64:-}" ]; then
        echo "[entrypoint] decoding SSH_PRIVATE_KEY_B64 -> ${KEY_FILE}"
        if ! printf '%s' "${SSH_PRIVATE_KEY_B64}" | base64 -d > "${KEY_FILE}" 2>/tmp/base64_err; then
            echo "[entrypoint] FATAL: SSH_PRIVATE_KEY_B64 base64 decode failed:" >&2
            cat /tmp/base64_err >&2
            exit 1
        fi
        printf '\n' >> "${KEY_FILE}"  # PEM trailing newline (see write_key)
        chmod 600 "${KEY_FILE}"
        if ! ssh-keygen -l -f "${KEY_FILE}" >/dev/null 2>&1; then
            echo "[entrypoint] FATAL: SSH_PRIVATE_KEY_B64 is valid base64 but not a valid SSH key" >&2
            head -c 200 "${KEY_FILE}" >&2; echo >&2
            exit 1
        fi
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
