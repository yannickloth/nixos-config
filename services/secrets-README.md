# /etc/secrets — README

This directory holds secrets for services configured in the NixOS flake
(`~/code/nixos-config`). Files here are intentionally **outside** the git repo —
never commit or share their contents.

Only the `secrets` group (`nicky`, `aeiuno`) plus root can read/write these
files. To edit, log in as one of them (after logging in once more to pick up
the group) and use your editor.

## opencode-keys.env

Holds the shared LLM provider keys for opencode. The source of truth is the
encrypted `secrets/opencode-keys.env.age` (committed to git). agenix decrypts it
here on every NixOS host; on CachyOS hosts the same `.age` file is decrypted
with the user key by home-manager (see `users/{nicky,aeiuno}/*-hm.nix`).

- Format: one line, `OPENAI_API_KEYS` set to a JSON object that maps each
  provider base URL to its API key:

      OPENAI_API_KEYS={"https://api.deepseek.com":"sk-your-deepseek-key"}

- The home-manager activation `setupOpenCodeKeys` (`users/opencode.nix`)
  materializes these entries as per-provider key files under
  `~/.config/opencode/keys/`. The generated `~/.config/opencode/opencode.json`
  reads those files through `{file:...}` substitution.
- On server-nike, `litellm-proxy-env.service` (`services/litellm-proxy.nix`)
  reads the same file and writes `/run/litellm-proxy.env` with the backend
  keys. The proxy unit's `EnvironmentFile=` exports them, and the store config
  references them through LiteLLM's `os.environ/VAR` resolver.
- hermes (Nicky only, `users/nicky/nicky-hm.nix`) reads the gateway master key
  and the z.ai / Kimi keys through `writeHermesEnv`, which upserts them as
  `LITELLM_MASTER_KEY`, `ZAI_CODING_API_KEY` and `KIMI_CODE_API_KEY` into
  `~/.hermes/.env` (referenced by hermes `custom_providers` via `key_env`).
  The running `hermes-gateway` service picks up rotated values on its next
  restart; every hermes CLI run loads the file fresh.

## litellm-db-password.age

Dedicated password for the `litellm` PostgreSQL role on server-nike. agenix
mounts it at `/run/agenix/litellm-db-password`; `litellm-proxy-env.service`
turns it into `DATABASE_URL=postgresql://litellm:...@127.0.0.1:5432/litellm`.
The role/database are created by `services/postgresql.nix` only when
`services.litellm-proxy.enable` is true. This is separate from nicky's own
PostgreSQL password (`pg-nicky-password.age`).

### Configured providers

| Provider | Base URL | Key file |
| --- | --- | --- |
| DeepSeek | `https://api.deepseek.com` | `deepseek.key` |
| Kimi for Coding | `https://api.kimi.com/coding/v1` | `kimi.key` |
| Hetzner AI | `https://inference.hetzner.com/api/v1` | `hetzner.key` |
| z.ai / GLM | `https://api.z.ai/api/coding/paas/v4` | `zai.key` |
| Unsloth Studio (key entry; every inference host's Studio keeps this same key) | `http://server-nike.bee-blues.ts.net:8888/v1` | `unsloth.key` |
| Cheaper Inference | `https://api.cheaperinference.com/v1` | `cheaperinference.key` |
| LiteLLM proxy (key entry; server-nike and laptop-p16 run the same master key) | `http://server-nike.bee-blues.ts.net:4000/v1` | `litellm-proxy.key` |

The z.ai entry may use either this coding-plan URL or the general
`https://api.z.ai/api/paas/v4/` URL; both resolve to `zai.key`.

### Adding another provider

1. Add the provider, its models and the base URL to `users/opencode.nix` (and
   to the `mapping` in `setupOpenCodeKeys`).
2. Add the matching key to `OPENAI_API_KEYS` in `secrets/opencode-keys.env.age`
   (see "Editing the secret" below).
3. Apply the config:
   ```
   sudo nixos-rebuild switch --flake ~/code/nixos-config
   ```
4. The activation writes the new key file. Start a new login session (or re-run
   the activation) so `setupOpenCodeKeys` picks it up.

### Editing the secret

The `.age` file in git is the source of truth. The decrypted copy in this
directory is writable for an immediate change, but the **next activation
overwrites it** from the `.age` file — make the change permanent in git.

```sh
# as nicky (her user key is a recipient):
nix run nixpkgs#agenix -- -e -i ~/.ssh/agenix_nicky secrets/opencode-keys.env.age

# as root on a NixOS host (the host key is a recipient):
sudo nix run nixpkgs#agenix -- -e -i /etc/ssh/ssh_host_ed25519_key secrets/opencode-keys.env.age

# then apply:
sudo nixos-rebuild switch --flake ~/code/nixos-config
```

### Where to get keys

- DeepSeek: https://platform.deepseek.com/api_keys (pay-per-token)
- Kimi for Coding: Kimi Code Platform subscription (key via the Kimi account /
  opencode auth); base URL `https://api.kimi.com/coding/v1`
- Hetzner AI: Hetzner Cloud AI token (key via the Hetzner console); base URL
  `https://inference.hetzner.com/api/v1`
- z.ai / GLM: a GLM Coding Plan subscription key (the z.ai console); a
  coding-plan key is rejected by the pay-per-token endpoint
- Cheaper Inference: the cheaperinference.com dashboard (a wallet-backed
  gateway; keys look like `ci_live_...`)
- Unsloth Studio: the server on server-nike; copy the key from Studio's
  Settings → API panel
- LiteLLM proxy: the master key is generated once (e.g.
  `python3 -c 'import secrets; print("sk-litellm-" + secrets.token_hex(32))'`)
  and stored under the proxy base URL; clients read it as
  `litellm-proxy.key`

### Note

The DeepSeek **API** is billed separately from the DeepSeek **app**
subscription.

## Related

- Provider and model list: `users/opencode.nix`.
- Per-user READMEs in each `~/README.md` (managed by `roles/home-readme.nix`).
