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
| `SSH_PRIVATE_KEY` | evet* | GitHub deploy SSH key. `-----BEGIN` ile başlıyorsa PEM olarak onarılır (newline/whitespace düzeltmesi dahil), başka türlü base64 olarak decode edilir. `*` = key yoksa ssh-agent kurulmaz, sadece web server ayağa kalkar |
| `SSH_PRIVATE_KEY_B64` | alternatif | Açıkça base64 olarak işaretlemek istersen (algılama yapmaz) |
| `OPENROUTER_API_KEY` | evet | OpenCode'un OpenRouter üzerinden LLM çağırması için |
| `OPENAI_API_KEY` | alternatif | OpenAI provider için |
| `ANTHROPIC_API_KEY` | alternatif | Anthropic provider için |
| `GIT_USER_NAME` | hayır | git commit'lerde görünecek isim (default: `opencode`) |
| `GIT_USER_EMAIL` | hayır | git commit'lerde görünecek e-posta (default: `opencode@localhost`) |
| `PORT` | hayır | Coolify inject eder; default 3000 |

### SSH Key'i Coolify'a koymak

Üç yol var; PEM formatı multiline/bozuk olsa bile entrypoint onarır, base64 tek satır olduğu için en sağlam seçenektir.

**Yol A — düz PEM (multiline, önerilen):**
```bash
# Coolify env editor'üne yapıştır
cat ~/.ssh/id_ed25519
```
> Coolify PEM gövdesindeki iç newline'ları bozsa bile (`tr '\n' ' '`, literal `\n`, CRLF, eksik trailing newline gibi) entrypoint onarır: header/footer'ı ayıklar, gövdedeki tüm whitespace'i siler, OpenSSH standardı olan 70 karakterlik satırlara yeniden böler ve sonuna newline ekler. Sonra `ssh-keygen -l` ile kriptografik olarak doğrular.

**Yol B — base64 (en sağlam, tek satır):**
```bash
base64 -w0 ~/.ssh/id_ed25519
# çıkan tek satırlık string'i SSH_PRIVATE_KEY olarak yapıştır
```
> Tek satır olduğu için Coolify bunu bozamaz. PEM yolu onarımına gerek kalmaz, doğrudan decode + `ssh-keygen -l` doğrulaması.

**Yol C — explicit base64 değişkeni (`SSH_PRIVATE_KEY_B64`):**
Base64 kullanmak istiyorsan ama `SSH_PRIVATE_KEY`'i başka amaçla meşgul etmek istemiyorsan. Açıkça base64 olarak işaretlenir, algılama yapılmaz.

Yol A veya B kullanıyorsan yalnız `SSH_PRIVATE_KEY` yeterli; üçünü birden set etme.

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
  1. `SSH_PRIVATE_KEY` (veya `SSH_PRIVATE_KEY_B64`) varsa akıllı decode: PEM ise onarım yapar (literal `\n` çevir, header/footer'ı ayıkla, whitespace'i sil, 70'li satırlara böl, trailing newline ekle), base64 ise decode + trailing newline ekle. `ssh-keygen -l` ile kriptografik geçerlilik doğrulanır; hangi yol geçerli key verdiyse o kullanılır
  2. `ssh-keyscan github.com` ile host doğrulamayı önceden yapar
  3. `git config --global` ayarlar
  4. `exec opencode serve --hostname 0.0.0.0 --port "$PORT"` ile süreci devralır
- **Healthcheck:** `HEALTHCHECK` direktifi `/global/health`'a `curl --fail` atar. Port `entrypoint.sh` tarafından `/root/.opencode_port`'a yazılır, böylece Coolify farklı `PORT` inject etse bile doğru port probe edilir. Coolify UI'da `Healthcheck Path = /global/health` ayarlanmalı.
