# /etc/secrets — README

This directory holds secrets for services configured in the NixOS flake
(`~/code/nixos-config`). Files here are intentionally **outside** the git repo —
never commit or share their contents.

Only the `secrets` group (`nicky`, `aeiuno`) plus root can read/write these
files. To edit, log in as one of them (after logging in once more to pick up
the group) and use your editor.

## open-webui.env

Configures the backend model provider(s) for the family AI chat
(Open WebUI, http://localhost:8080). Open WebUI talks to OpenAI-compatible
APIs.

- The list of providers (base URLs) is declared in `services/ai-chat.nix` as
  `OPENAI_API_BASE_URLS` (kept in git — URLs are not secret).
- The matching API keys go **here**, in `/etc/secrets/open-webui.env`, as a
  JSON object mapping each base URL to its key:

      OPENAI_API_KEYS={"https://api.deepseek.com":"sk-your-deepseek-key"}

### Adding another provider

1. Add its base URL to `OPENAI_API_BASE_URLS` in `services/ai-chat.nix`, e.g.
   `["https://api.deepseek.com","https://api.openai.com/v1"]`.
2. Add the matching key entry to `OPENAI_API_KEYS` in this file.
3. Apply, then reload the keys:
   ```
   sudo nixos-rebuild switch --flake ~/code/nixos-config
   sudo systemctl restart open-webui
   ```
4. The new provider appears in Open WebUI (Models → select provider).

### Where to get keys

- DeepSeek: https://platform.deepseek.com/api_keys (pay-per-token)
- OpenAI:   https://platform.openai.com/api-keys
- Groq:     https://console.groq.com/keys
- Ollama (local, free, no key): add `"http://localhost:11434"` to
  `OPENAI_API_BASE_URLS` and give it any key, e.g. `"ollama"`.

### Note

The DeepSeek **API** is billed separately from the DeepSeek **app**
subscription.

## Related

- Kid-safety chat gate: `services/ai-chat/filters/kid-safety.py` (versioned in
  git), seeded into Open WebUI's DB by the `open-webui-seed-gates` service.
- Per-user READMEs in each `~/README.md` (managed by `roles/home-readme.nix`).
