# `secrets/` — what lives here (and why it's never committed)

`secrets/` at the repo root is the **single source of truth for every secret**
this config expects. The real files are gitignored (`secrets/**` in
`.gitignore`) and must **never** be committed. This `secrets-structure/` tree
only mirrors the expected layout so a fresh checkout shows what goes where.

Each secret is provisioned from `secrets/` to the runtime path the service
reads (see `services/secrets.nix` and the syncthing activation script).
Irreversible hashes (e.g. user password hashes in `users/*.nix`) stay
committed in git.

The **exact format** of each credential text file is shown by the tracked
`*.example` files in this folder (copy one to `secrets/` and fill in the real
value). The `syncthing/<host>/` subdirs intentionally hold no examples — their
`cert.pem`/`key.pem` are generated (see `syncthing/<host>/` below).

## Expected layout

```
secrets/
├── syncthing/
│   ├── laptop-p16/     cert.pem, key.pem   # device VCAGGHS-…
│   ├── laptop-hera/    cert.pem, key.pem   # device 6RRKHEE-…
│   └── laptop-xps/     cert.pem, key.pem   # device MMPI6MM-…
├── cifs/
│   └── nestor.secrets                      # CIFS client creds for nestor mount
├── syncthing-gui-password                  # Syncthing web UI (shared)
├── open-webui.env                          # Family AI chat (OPENAI_API_KEYS)
└── nicky.nix                               # AI API keys (DeepSeek, Z_AI)
```

Exact formats (fill in the values, copy to `secrets/`):

```
# cifs/nestor.secrets.example -> secrets/cifs/nestor.secrets
username=your-cifs-username
password=your-cifs-password

# syncthing-gui-password.example -> secrets/syncthing-gui-password
<a strong shared password>

# open-webui.env.example -> secrets/open-webui.env
OPENAI_API_KEYS={"https://api.deepseek.com":"sk-your-deepseek-key","https://api.kimi.com/coding/v1":"sk-kimi-your-key","https://inference.hetzner.com/api/v1":"your-hetzner-key"}

# nicky.nix.example -> secrets/nicky.nix
{
  ZAI_CODING_PLAN_API_KEY = "PUT_YOUR_API_KEY_HERE";
  DEEPSEEK_API_KEY = "sk-your-deepseek-key";
}
```

## Per-file details

### `syncthing/<host>/cert.pem` + `key.pem`
- **What:** Syncthing node identity for each host. `cert.pem` is public, but
  `key.pem` authenticates the host to every peer and grants full read access to
  all synced folders — keep both secret.
- **Runtime path:** copied to `/etc/nixos/secrets/syncthing/<host>/` by the
  syncthing activation script.
- **Rule:** device ID (public) is committed in `services/syncthing/pool.nix`;
  the cert/key must **never** be committed. Back them up in **KeePass**.
- **Provisioning order** (if missing at runtime): pre-generated staging copy →
  existing `/var/lib/syncthing` → fresh `syncthing generate` (changes the ID).

### `syncthing-gui-password`
- **What:** plaintext password for the Syncthing web UI (`http://<host>:8384`),
  a single shared credential for nicky + aeiuno (Syncthing has one user).
- **Format:** see `syncthing-gui-password.example`.
- **Runtime path:** `/etc/secrets/syncthing-gui-password` (group `syncthing`),
  hashed by the module at activation.
- **Provisioned by:** `services/secrets.nix`.

### `open-webui.env`
- **What:** env file with `OPENAI_API_KEYS` mapping provider URLs to API keys
  for the family AI chat (Open WebUI). One entry per provider.
- **Providers:** DeepSeek (`api.deepseek.com`), Kimi for Coding
  (`api.kimi.com/coding/v1`), Hetzner AI (`inference.hetzner.com/api/v1`) —
  base URLs are declared in `services/ai-chat.nix`
  (`OPENAI_API_BASE_URLS`); only the keys are secret here.
- **Format:** see `open-webui.env.example`; details in
  `services/ai-chat/secrets-README.md`.
- **Runtime path:** `/etc/secrets/open-webui.env` (group `secrets`).
- **Provisioned by:** `services/secrets.nix`.

### `cifs/<mount>.secrets`
- **What:** CIFS **client** credentials used by a single mount, `username=…`/
  `password=…`. One file per mount — it is **not** a global secret. To add a
  mount, add its own `secrets/cifs/<name>.secrets` and reference it from a
  `cifs-<name>.nix` module; `services/secrets.nix` provisions every
  `secrets/cifs/*.secrets` to `/etc/nixos/cifs/<name>.secrets`.
- **Format:** see `cifs/nestor.secrets.example`.
- **Runtime path:** `/etc/nixos/cifs/<name>.secrets` (root-owned, mode 0600).
- **Provisioned by:** `services/secrets.nix`. Read by the matching
  `services/cifs-*.nix` (e.g. `cifs-nestor.nix`).

> **SMB server vs client auth:** Samba **server** shares (`services/samba.nix`)
> authenticate each connecting client with its own OS account — who may connect
> is set per share via `"valid users"`, and each user's SMB password is stored
> server-side via `smbpasswd`. The `cifs/*.secrets` files here are only for the
> **client** side (mounting remote shares), where one identity per mount is
> used.

### `nicky.nix`
- **What:** AI-chat API keys for nicky, a Nix attrset
  (`ZAI_CODING_PLAN_API_KEY`, `DEEPSEEK_API_KEY`).
- **Format:** see `nicky.nix.example` (also `users/nicky/secrets.example.nix`).
- **Runtime:** imported directly by `users/nicky/nicky-hm.nix` (falls back to
  empty if absent).

## Rules

- **Never commit** any file under `secrets/` (cert/key, GUI password, env,
  smb credentials, API keys). `.gitignore` has `secrets/**`.
- The **expected tree only** is tracked here in `secrets-structure/`.
- Back up the secrets in **KeePass** so a wiped disk can be re-seeded.
- Keep `secrets/syncthing.zip` (if present) out of git too.
- If a new service needs a secret, add it under `secrets/`, document it here,
  and provision it in `services/secrets.nix`.
