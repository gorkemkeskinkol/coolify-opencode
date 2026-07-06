# coolify-opencode

OpenCode'u Coolify üzerinde headless web servisi olarak çalıştıran, GitHub'a SSH agent üzerinden erişen, OpenRouter API key'i env ile verilen minimal Docker imajı. Projeler ve opencode state iki ayrı volume'de kalıcıdır; image yeniden deploy edildiğinde kullanıcı dosyaları ve düzenlenen config kaybolmaz.

## Coolify Servis Tanımı (Description)

> **Headless OpenCode server in a Docker container — exposes its web UI on `PORT` (default 3000), with a startup ssh-agent that injects the `SSH_PRIVATE_KEY` env var for transparent GitHub access. LLM auth via env-injected API keys (e.g. `OPENROUTER_API_KEY`). Two persistent volumes: `/projects` (user work) and `/opencode` (session DB + global config). Designed for one-click deploy on Coolify behind a Cloudflare Tunnel; no local Docker required.**

## Coolify'da Kurulum

### 1. Resource

| Ayar | Değer |
|---|---|
| Build Pack | `Dockerfile` |
| Port | `3000` (veya Coolify'ın atadığı `PORT`) |
| Healthcheck Path | `/global/health` |
| Healthcheck Method | `GET` |
| Healthcheck Interval | `30s` |
| Healthcheck Timeout | `5s` |
| Healthcheck Start Period | `15s` |

### 2. Persistent Storages (iki ayrı volume tanımla)

| Mount Path | Açıklama |
|---|---|
| `/projects` | Kullanıcı projeleri. OpenCode burada çalışır, dosya oluşturur/düzenler. |
| `/opencode` | OpenCode session DB, snapshot'lar, repo'lar, global config (`opencode.jsonc`, `AGENTS.md`). |

> Container içinde `WORKDIR=/projects`. `XDG_*_HOME` env'leri `/opencode` altına yönlendirildiği için opencode tüm kalıcı verisini bu volume'e yazar. İkisi de Coolify service'ine "Persistent Storage" olarak eklenmeli — image redeploy'larında içerik korunur.

### 3. Environment Variables

| Değişken | Zorunlu | Açıklama |
|---|---|---|
| `OPENROUTER_API_KEY` | evet | OpenRouter üzerinden LLM çağrıları. opencode env'den otomatik okur, `auth.json` yazmaya gerek yok |
| `OPENAI_API_KEY` | alternatif | OpenAI provider |
| `ANTHROPIC_API_KEY` | alternatif | Anthropic provider |
| `SSH_PRIVATE_KEY` | hayır* | GitHub deploy SSH key. `-----BEGIN` ile başlıyorsa PEM olarak onarılır, başka türlü base64 decode edilir. `*` = yoksa ssh-agent kurulmaz |
| `SSH_PRIVATE_KEY_B64` | alternatif | Açıkça base64 olarak işaretlemek istersen |
| `GIT_USER_NAME` | hayır | git commit'lerde görünecek isim (default: `opencode`) |
| `GIT_USER_EMAIL` | hayır | git commit'lerde görünecek e-posta (default: `opencode@localhost`) |
| `OPENCODE_SERVER_PASSWORD` | **önerilir** | Public expose için HTTP Basic Auth. Set edilmezse server unsecured olur, uyarı log'a düşer |
| `OPENCODE_SERVER_USERNAME` | hayır | Basic Auth kullanıcı adı (default: `opencode`) |
| `PORT` | hayır | Coolify inject eder; default 3000 |

### SSH Key'i Coolify'a koymak

**Yol A — düz PEM (multiline, önerilen):**
```bash
# Coolify env editor'üne yapıştır
cat ~/.ssh/id_ed25519
```
Coolify PEM gövdesindeki iç newline'ları bozsa bile (`tr '\n' ' '`, literal `\n`, CRLF, eksik trailing newline) entrypoint onarır ve `ssh-keygen -l` ile kriptografik olarak doğrular.

**Yol B — base64 (en sağlam, tek satır):**
```bash
base64 -w0 ~/.ssh/id_ed25519
# çıkan tek satırlık string'i SSH_PRIVATE_KEY olarak yapıştır
```

**Yol C — explicit base64 (`SSH_PRIVATE_KEY_B64`):**
`SSH_PRIVATE_KEY`'i başka amaçla meşgul etmek istemiyorsan.

Yol A veya B yeterli; üçünü birden set etme.

## OpenCode Config ve Sistem Context

### Default config seed
Image içinde iki seed dosyası gelir:
- `opencode.jsonc` — model/provider ayarları (`plan: claude-opus-4.8`, `build: minimax-m3`, OpenRouter üzerinden), `instructions: ["AGENTS.md", ".rules/*.md"]`, `lsp: true`.
- `AGENTS.md` — self-host sistem context'i: coolify/container kısıtlamaları, lokal docker yasağı, "/projects dışına yazma" kuralı.

İlk kalkışta bu dosyalar `/opencode/config/opencode/` altına kopyalanır. **Sonraki deploy'larda kullanıcı bu dosyaları düzenlediyse üzerine yazılmaz** (`cp -n` semantiği ile idempotent). Yani:
- Yeni sürümde config değişirse → kullanıcı kendi volume'ünden dosyayı silmeli ki seed tekrar uygulansın.
- Kullanıcı düzenlemesi yaptıysa → korunur.

### Sistem context (`AGENTS.md`)
OpenCode'a her session'da şu context enjekte olur:
- Self-hosted Coolify container içinde çalışıyorsun, host senin değil.
- Lokal Docker build/test yapma; deploy sonuçlarını kullanıcıdan iste.
- `/projects` ve `/opencode` dışına yazma (image-shipped veya ephemeral alanlar).
- `apt`, `npm install -g` gibi container-mutating install'ları yapma.
- SSH sadece `github.com` için scope'ludur.

## Cloudflare Tunnel

`cloudflared` Coolify sunucusunda çalıştığı için tunnel'ı Cloudflare dashboard'dan ekle:

- **Type:** HTTP
- **URL:** `http://<coolify-service-host>:<port>` (Coolify otomatik service host atar)
- **No TLS Verify:** açık (Coolify local trafiği HTTP'dir)

HTTPS termination Cloudflare tarafında yapılır. Public expose için mutlaka `OPENCODE_SERVER_PASSWORD` set et.

## Lokal Build

```bash
docker build -t coolify-opencode:dev .
docker run --rm -p 3000:3000 \
  -e OPENROUTER_API_KEY=sk-or-... \
  -e SSH_PRIVATE_KEY="$(cat ~/.ssh/id_ed25519)" \
  -v "$(pwd)/playground-projects:/projects" \
  -v "$(pwd)/playground-opencode:/opencode" \
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
│  ├─ WORKDIR /projects   (volume: user)      │
│  ├─ XDG_*_HOME → /opencode/* (volume: data) │
│  └─ AGENTS.md context (self-host rules)     │
└─────────────────────────────────────────────┘
```

## İç Yapı

- **Base:** `node:22-slim` (glibc, opencode native binary için)
- **OpenCode:** resmi installer ile kurulu, sürüm `Dockerfile` içinde pinli (`ARG OPENCODE_VERSION`)
- **Volume'ler:** `WORKDIR=/projects`, `VOLUME ["/projects", "/opencode"]`
- **XDG yönlendirmesi:** `XDG_DATA_HOME=/opencode/data`, `XDG_CONFIG_HOME=/opencode/config`, `XDG_STATE_HOME=/opencode/state`, `XDG_CACHE_HOME=/opencode/cache`
- **Entrypoint:** `entrypoint.sh`
  1. XDG env'lerini set eder, `/projects` ve `/opencode` alt ağaçlarını oluşturur
  2. `OPENROUTER_API_KEY` varsa log'lar, yoksa uyarı basar
  3. `SSH_PRIVATE_KEY` (veya `SSH_PRIVATE_KEY_B64`) varsa akıllı decode: PEM ise onarım yapar (literal `\n` çevir, header/footer'ı ayıkla, whitespace'i sil, 70'li satırlara böl, trailing newline ekle), base64 ise decode + trailing newline ekle. `ssh-keygen -l` ile kriptografik geçerlilik doğrulanır
  4. İlk kalkışta `/opt/opencode-seed/`'deki `opencode.jsonc` ve `AGENTS.md`'yi `/opencode/config/opencode/` altına idempotent olarak kopyalar (kullanıcı düzenlemesi varsa ezmez)
  5. `ssh-keyscan github.com` ile host doğrulamayı önceden yapar
  6. `git config --global` ayarlar
  7. `cd /projects && exec opencode serve --hostname 0.0.0.0 --port "$PORT"` ile süreci devralır
- **Healthcheck:** `HEALTHCHECK` direktifi `/global/health`'a `curl --fail` atar. Port `entrypoint.sh` tarafından `/root/.opencode_port`'a yazılır, böylece Coolify farklı `PORT` inject etse bile doğru port probe edilir. Coolify UI'da `Healthcheck Path = /global/health` ayarlanmalı.
