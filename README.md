# coolify-opencode

OpenCode'u Coolify üzerinde headless web servisi olarak çalıştıran, GitHub'a SSH agent üzerinden erişen minimal Docker imajı.

## Coolify Servis Tanımı (Description)

> **Headless OpenCode server in a Docker container — exposes its web UI on `PORT` (default 3000), with a startup ssh-agent that injects the `SSH_PRIVATE_KEY` env var for transparent GitHub access. Built for one-click deploy on Coolify behind a Cloudflare Tunnel; LLM auth is via env-injected API keys (e.g. `OPENROUTER_API_KEY`).**

## Coolify'da Kurulum

| Ayar | Değer |
|---|---|
| Build Pack | `Dockerfile` |
| Port | `3000` (veya Coolify'ın atadığı `PORT`) |
| Healthcheck Path | `/global/health` |
| Healthcheck Method | `GET` |
| Healthcheck Interval | `30s` |
| Healthcheck Timeout | `5s` |
| Healthcheck Start Period | `15s` |

Coolify tarafı otomatik olarak `PORT` env'ini inject eder; servisi `0.0.0.0:$PORT` üzerinde dinler.

## Environment Variables

| Değişken | Zorunlu | Açıklama |
|---|---|---|
| `SSH_PRIVATE_KEY_B64` | evet* | GitHub deploy SSH key, **base64** encode edilmiş. `*` = key yoksa ssh-agent kurulmaz, sadece web server ayağa kalkar |
| `SSH_PRIVATE_KEY` | alternatif | Base64 yerine düz PEM (multiline). PEM trailer newline'ı korunmalı, garanti değilse base64 tercih et |
| `OPENROUTER_API_KEY` | evet | OpenCode'un OpenRouter üzerinden LLM çağırması için |
| `OPENAI_API_KEY` | alternatif | OpenAI provider için |
| `ANTHROPIC_API_KEY` | alternatif | Anthropic provider için |
| `GIT_USER_NAME` | hayır | git commit'lerde görünecek isim (default: `opencode`) |
| `GIT_USER_EMAIL` | hayır | git commit'lerde görünecek e-posta (default: `opencode@localhost`) |
| `PORT` | hayır | Coolify inject eder; default 3000 |

### SSH Key'i Coolify'a koymak

Base64 tavsiye edilir (Coolify multiline env'de sondaki newline'ı yiyor, bu da OpenSSH PEM parser'ı bozarak `Error loading key ... error in libcrypto` hatasına yol açar):

```bash
base64 -w0 ~/.ssh/id_ed25519 > /tmp/key.b64
# bu tek satırlık base64 string'i SSH_PRIVATE_KEY_B64 olarak yapıştır
```

`SSH_PRIVATE_KEY` (düz PEM) kullanırsan son satır mutlaka `-----END OPENSSH PRIVATE KEY-----` olmalı ve ondan sonra bir boş satır olmalı. Yine de base64 daha güvenilir.

## Cloudflare Tunnel

`cloudflared` Coolify sunucusunda çalıştığı için tunnel'ı Cloudflare dashboard'dan ekle:

- **Type:** HTTP
- **URL:** `http://<coolify-service-host>:<port>` (Coolify otomatik service host atar)
- **No TLS Verify:** açık (Coolify local trafiği HTTP'dir)

HTTPS termination Cloudflare tarafında yapılır.

## Lokal Build

```bash
docker build -t coolify-opencode:dev .
docker run --rm -p 3000:3000 \
  -e OPENROUTER_API_KEY=sk-or-... \
  -e SSH_PRIVATE_KEY="$(cat ~/.ssh/id_ed25519)" \
  coolify-opencode:dev
```

## Mimari

```
┌─────────────────────────────────────────────┐
│  Cloudflare Edge (TLS termination)          │
└─────────────────┬───────────────────────────┘
                  │ HTTPS
┌─────────────────▼───────────────────────────┐
│  Cloudflare Tunnel (cloudflared)            │
└─────────────────┬───────────────────────────┘
                  │ HTTP
┌─────────────────▼───────────────────────────┐
│  Coolify (reverse proxy + PORT injection)  │
└─────────────────┬───────────────────────────┘
                  │ HTTP
┌─────────────────▼───────────────────────────┐
│  Container: opencode serve --hostname 0.0.0.0 --port $PORT
│  ├─ ssh-agent (SSH_PRIVATE_KEY)             │
│  └─ git config (GIT_USER_NAME/EMAIL)        │
└─────────────────────────────────────────────┘
```

## İç Yapı

- **Base:** `node:22-slim` (glibc, opencode native binary için)
- **OpenCode:** resmi installer ile kurulu, sürüm `Dockerfile` içinde pinli (`ARG OPENCODE_VERSION`)
- **Entrypoint:** `entrypoint.sh`
  1. `SSH_PRIVATE_KEY` varsa `~/.ssh/id_ed25519`'e yazar, `ssh-agent` başlatır, key'i ekler
  2. `ssh-keyscan github.com` ile host doğrulamayı önceden yapar
  3. `git config --global` ayarlar
  4. `exec opencode serve --hostname 0.0.0.0 --port "$PORT"` ile süreci devralır
- **Healthcheck:** `HEALTHCHECK` direktifi `/global/health`'a `curl --fail` atar. Port `entrypoint.sh` tarafından `/root/.opencode_port`'a yazılır, böylece Coolify farklı `PORT` inject etse bile doğru port probe edilir. Coolify UI'da `Healthcheck Path = /global/health` ayarlanmalı.
