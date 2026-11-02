# /etc/secrets — README

This directory holds secrets for services configured in the NixOS flake
(`~/code/nixos-config`). Files here are intentionally **outside** the git repo —
never commit or share their contents.

Only the `secrets` group (`nicky`, `aeiuno`) plus root can read/write these
files. To edit, log in as one of them (after logging in once more to pick up
the group) and use your editor.

## open-webui.env

The family's AI provider API keys, as a single JSON object mapping each
provider's base URL to its key:

    OPENAI_API_KEYS={"https://api.deepseek.com":"sk-your-deepseek-key"}

The file name is historical (it used to be Open WebUI's EnvironmentFile; the
service is gone). Its consumer now is the opencode / pi key materialization
(`users/opencode.nix`, activation step `setupOpenCodeKeys`), which reads the
JSON at login and writes one key file per provider into each adult's
`~/.config/opencode/keys/`.

### Configured providers

| Provider | Base URL (as stored in the JSON) | Key |
| --- | --- | --- |
| DeepSeek | `https://api.deepseek.com` | DeepSeek API key |
| Kimi for Coding | `https://api.kimi.com/coding/v1` | Kimi subscription key |
| Z.AI GLM Coding Plan | `https://api.z.ai/api/paas/v4/` (opencode talks to the `.../coding/paas/v4` endpoint) | GLM coding-plan key |
| Hetzner AI | `https://inference.hetzner.com/api/v1` | Hetzner AI token |
| Unsloth Studio (local) | `http://127.0.0.1:8888/v1` | the Studio key |

### Adding another provider

1. Add the matching key entry to `OPENAI_API_KEYS` in this file.
2. The provider must also be configured in `users/opencode.nix` (the
   `providers` table) and its base URL must appear in the `mapping` dict of
   the `setupOpenCodeKeys` activation — otherwise the key is silently skipped.
3. Apply, then log out and back in (the key files are materialized at login).

### Where to get keys

- DeepSeek: https://platform.deepseek.com/api_keys (pay-per-token)
- Kimi for Coding: Kimi Code Platform subscription (key via the Kimi account /
  opencode auth); base URL `https://api.kimi.com/coding/v1`
- Z.AI GLM: GLM Coding Plan subscription (key via the Z.AI console); opencode
  talks to `https://api.z.ai/api/coding/paas/v4`
- Hetzner AI: Hetzner Cloud AI token (key via the Hetzner console); base URL
  `https://inference.hetzner.com/api/v1`
- OpenAI:   https://platform.openai.com/api-keys
- Groq:     https://console.groq.com/keys

### Note

The DeepSeek **API** is billed separately from the DeepSeek **app**
subscription.

## Related

- Per-user READMEs in each `~/README.md` (managed by `roles/home-readme.nix`).
