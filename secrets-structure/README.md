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
├── syncthing-gui-password                  # Syncthing web UI (shared)
├── open-webui.env                          # Family AI chat (OPENAI_API_KEYS)
├── smb-secrets                             # CIFS/nestor credentials
└── nicky.nix                               # AI API keys (DeepSeek, Z_AI)
```

Exact formats (fill in the values, copy to `secrets/`):

```
# syncthing-gui-password.example -> secrets/syncthing-gui-password
<a strong shared password>

# open-webui.env.example -> secrets/open-webui.env
OPENAI_API_KEYS={"https://api.deepseek.com":"sk-your-deepseek-key"}

# smb-secrets.example -> secrets/smb-secrets
username=your-cifs-username
password=your-cifs-password

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
  for the family AI chat (Open WebUI).
- **Format:** see `open-webui.env.example`; details in
  `services/ai-chat/secrets-README.md`.
- **Runtime path:** `/etc/secrets/open-webui.env` (group `secrets`).
- **Provisioned by:** `services/secrets.nix`.

### `smb-secrets`
- **What:** CIFS credentials for the nestor shares, `username=…`/`password=…`.
- **Format:** see `smb-secrets.example`.
- **Runtime path:** `/etc/nixos/smb-secrets` (root-owned, mode 0600).
- **Provisioned by:** `services/secrets.nix`. Read by `services/cifs-nestor.nix`.

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
