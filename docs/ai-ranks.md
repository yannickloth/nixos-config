# AI Ranks — Belgian Air Component

All rank names in English, using the Belgian Air Component (Luchtcomponent / Force aérienne) structure. The complete hierarchy provides room for many models to be slotted in without saturation.

**A rank name is a pure abstraction over the models currently holding the slot.** It never contains a model name, provider name, or implementation detail (dense/sparse, quant, backend). The only permitted suffix is a *feature* suffix — currently `-v` for the vision-capable slot of a rank. **Multiple models may share one rank** (docs/ai-ranks.md is the source of truth; the proxy lists them as multiple deployments under a single model name).

**The ladder now covers every model of every ranked provider** — Z.ai Coding Plan, Kimi Code (legacy **Allegretto** plan), DeepSeek API, Hetzner Inference — plus the three local models. The CheaperInference reseller catalogue (OpenAI/Anthropic) stays *outside* the ladder: the explicit pay-as-you-go pool, escalated by explicit selection, promoted to a general-officer rank only when a model moves into standing use.

Research date: 2026-11-21. Sources: Kimi Code docs (`kimi.com/code/docs/en/kimi-code/models`, `.../membership`) plus the live `GET /coding/v1/models` metadata, Z.ai docs (GLM-5.3, GLM-5.3-Flash/FlashX, and the devpack model-switching pages), DeepSeek API docs (`api-docs.deepseek.com` models & pricing, `GET /v1/models`), Hetzner docs (Inference API) plus the live route probe, hermes-agent #18990 / PR #18999 (third-party pixel tests against the Kimi coding endpoint, 2026-09/11), plus the repo's own pixel-color verification notes.

## Ranking rules

1. **Capability decides the slot.** Size bands are approximate and written for dense models; MoE models are slotted by capability (active params + knowledge capacity), not total params.
2. **Intra-rank deployment order** (proxy `litellm_params.order`, lowest first) is the standing rule: **subscription quota → pay-per-token API → free cloud → local**. A quota-exhausted subscription falls to the next tier, never the other way round.
3. **Every model of a ranked provider holds a slot**, including variants we deliberately do not deploy (high-speed twins, legacy auto-routed aliases): they are mapped to the slot of their standard twin so the ladder stays complete, and are excluded from deployments by the high-speed policy (below).
4. **Each ranked model also has one explicit proxy name**, spelled exactly like the upstream id (`k3.1-pro`, `glm-5.3-flash`, `deepseek-flash`, the four Hetzner ids, ...) for callers that want the model itself rather than a rank. A name never hides a cost class: the plan `glm-5.3` draws subscription quota, the cash twin `glm-5.3-payg` draws per-token billing.
5. **Paid ranks are explicit selections** — no cross-rank fallback in or out (silent cost escalation is worse than a visible error). The auto cascade stays inside the free stack.
6. **Vision lives on `-v` slots.** Plain ranks are text-only by contract even when their model is multimodal; every deployment behind a `-v` name is itself image-capable (verified where marked, provider-spec where marked TODO).

## Enlisted (OR-1 to OR-4)

| NATO | English | Model | Source | Purpose |
|---|---|---|---|---|
| OR-1 | **Private** | | | Sub-1B models. Space for tiny executors later. |
| OR-2 | **Corporal** | | | 1–3B models. Space for smaller executors. |
| OR-3 | **Corporal Chief** | | | 3–5B models. |
| OR-4 | **Sergeant** | `unsloth/NVIDIA-Nemotron-3.5-Bolt-E4B-GGUF` | Unsloth Studio (local) | Fast executor. Faithful instruction following, subagent-level tasks. |

## Warrant Officers (OR-5 to OR-9)

| NATO | English | Model | Source | Purpose |
|---|---|---|---|---|
| OR-5 | **First Sergeant** | | | 5–10B models. |
| OR-6 | **First Sergeant Chief** | | | 10–15B models. |
| OR-7 | **First Sergeant Major** | | | 15–20B models. |
| OR-8 | **Warrant Officer** | `Qwen/Qwen3.6-35B-A3B-FP8` (cloud) · `unsloth/Qwen3.6-35B-A3B-MTP-GGUF` (local) | Hetzner (free cloud) + Unsloth Studio | Workhorse. One rank, two deployments of the same model — free-cloud primary, local fallback. Natively multimodal model; the vision slot is the sibling rank `warrant-officer-v` (same model). |
| OR-9 | **Chief Warrant Officer** | | | Reserved. |

## Junior Officers (OF-1a to OF-2)

| NATO | English | Model | Source | Purpose |
|---|---|---|---|---|
| OF-1a | **Second Lieutenant** | `Qwen3.8-27B` | Hetzner Inference (free cloud) | The 27B base model of Swift 1.5 (same architecture, minus post-training). Cleaner output, ~28 tok/s. |
| OF-1b | **Lieutenant** | `swift-1.5-iq3_xxs` | Strata (local) | **Default model.** Deep reasoning, 128K context (the window Strata serves on the p16 card — `--max-context 131072`, live `n_ctx 131072`; the 384K the model supports natively is not served here). Smart, reliable, delegates to lower ranks. Natively multimodal model; the vision slot is the sibling rank `lieutenant-v` (same model). |
| OF-2 | **Captain** | `deepseek-flash` (DeepSeek-V4.1-Flash-1017) | DeepSeek API (pay-per-token) | Cheapest paid coder above the free stack: 1M ctx, 384K out, image input, fastest in the pool. Vision slot: `captain-v`. $0.15/$0.60 off-peak. |

## Senior Officers (OF-3 to OF-5)

| NATO | English | Model | Source | Purpose |
|---|---|---|---|---|
| OF-3 | **Captain Commandant** | `glm-5-turbo` → `deepseek-v4-pro` | Z.ai Coding Plan → DeepSeek API | The mid paid coders, subscription first. `glm-5-turbo`: plan quota, 200K ctx, the GLM-5-generation turbo. `deepseek-v4-pro` (V4-Pro-0813): 1.6T params, hardest reasoning, best agentic knowledge, $0.66/$1.98 off-peak. Both text-only — no `-v` slot. |
| OF-4 | **Major** | `kimi-for-coding` (K2.8) → `glm-5.3-flash` → `deepseek-v4-pro` | Kimi → Z.ai → DeepSeek | Strong, not frontier. Order 1 `kimi-for-coding`: K2.8 Preview, performance close to K3, 1M. Order 2 `glm-5.3-flash`: native multimodal MoE (18B active), 1M, **3× the quota of glm-5.3** — a clear tier below it, hence Major and not Lieutenant Colonel. Order 3 `deepseek-v4-pro` (pay-per-token twin). Vision slot: `major-v` = `kimi-for-coding` (order 1 — image-capable per the docs and the live endpoint metadata, see Vision verification) → `glm-5.3-flash` (order 2, the 3×-quota fallback). |
| OF-5 | **Lieutenant Colonel** | `glm-5.3` → `k3` → `k3-256k` | Z.ai → Kimi | The frontier tier, all subscription. `glm-5.3`: dense flagship, 1M, text-only, SWE-bench Verified 95.4. `k3`: 2.8T / 104B active, 1M on Allegretto, natively multimodal, ties GLM-5.3 on the Intelligence Index (SWE-bench 93.4). `k3-256k`: same model, 262K window, ~half the quota. |
| OF-5 | **Lieutenant Colonel** (vision) | `k3` → `k3-256k` | Kimi | The rank's image-capable deployments (model table: image+video for k3, image only for k3-256k; live `GET /coding/v1/models` confirms `supports_image_in: true`, third-party pixel tests answered correctly — see Vision verification). `glm-5.3` is absent — text-only model. |

## General Officers (OF-6 to OF-9)

| NATO | English | Model | Source | Purpose |
|---|---|---|---|---|
| OF-6 | **Brigadier General** | `k3.1-pro` | Kimi (Allegretto) | The strongest model in the stack: 3T-class flagship, 1M context (Allegretto's 1M tier), **thinking-only** — requests with thinking disabled are rejected; the proxy pins `reasoning_effort: high`. Vision slot: `brigadier-general-v` (model table: image+video; live pixel test 2026-11-17 answered correctly — see Vision verification). |
| OF-6 | **Brigadier General** (vision) | `k3.1-pro` | Kimi | The `-v` sibling of Brigadier General. |
| OF-7 | **Major General** | | | Reserved: paid model promoted to standing use. |
| OF-8 | **Lieutenant General** | | | Reserved: paid model promoted to standing use. |
| OF-9 | **General** | | | Reserved: paid model promoted to standing use. |

## Complete model → rank mapping

Every model id served by the four ranked providers, mapped to its rank. "Deployed" = wired in `services/litellm-proxy.nix`; "documented" = mapped to a rank but not deployed (high-speed policy or legacy alias).

### Z.ai Coding Plan (`https://api.z.ai/api/coding/paas/v4`, subscription)

| Model ID | Rank | Deployed | Notes |
|---|---|---|---|
| `glm-5.3` | Lieutenant Colonel (OF-5) | yes | Dense 92-layer flagship, 1M ctx, 128K (131,072) out, text-only. **Reasoning always on** — `thinking: disabled` requests are rejected; `reasoning_effort` low/high/max, default max (Z.ai recommends `max` for agent work). Credit mult 6.9/1.7/24. Off-peak (weekends + Mon–Fri 06:00–10:00 UTC) at 50% credits. |
| `glm-5.3-highspeed` | Lieutenant Colonel (OF-5) | no | Same model on faster GPU. Not deployed per the high-speed policy (same output, same quota class). |
| `glm-5.3-flash` | **Major (OF-4)** — a tier below `glm-5.3` | yes | Sparse MoE (320B total / 18B active), **native multimodal** — the first GLM with video/image/text/file input, 1M ctx, 128K out, 3× the quota of `glm-5.3`, cheaper credits (2.3/0.56/8). Reasoning always on; Z.ai recommends `reasoning_effort: max`. |
| `glm-5-turbo` | Captain Commandant (OF-3) | yes | GLM-5-generation turbo, 200K ctx, 131K out, text-only. |
| `glm-5.2` | Lieutenant Colonel (OF-5) | no (alias) | Auto-routed to `glm-5.3` on the plan; consumes GLM-5.3 credits. Serves the same deployment, so it holds the same rank without its own proxy entry. |
| `glm-5.2-highspeed` | Lieutenant Colonel (OF-5) | no (alias) | High-speed twin of the `glm-5.2` alias. |
| `glm-5.1` | Lieutenant Colonel (OF-5) | no (alias) | Auto-routed to `glm-5.3`; same credits. |
| `glm-4.7` | Major (OF-4) | no (alias) | Auto-routed to `glm-5.3-flash` on the plan; consumes flash credits. |
| `glm-5.3-flashx` | Major (OF-4) | no | Pay-per-token Standard API only (officially not on the Coding Plan). Same model, faster serving. |
| `glm-5.3-flashx-legal` | Major (OF-4) | no | Specialized (legal) twin of `glm-5.3-flash`; Standard API only. Not needed for agent work. |

### Kimi Code — legacy Allegretto plan (`https://api.kimi.com/coding/v1`, subscription)

Allegretto is a **legacy** plan (the new ladders are Plus/Pro/Max/Ultra). On Allegretto: Kimi Code is entitled, `k3.1-pro` and `k3` get **1M context** (the 1M tier unlocks at Allegretto), and every HighSpeed id is available.

| Model ID | Rank | Deployed | Notes |
|---|---|---|---|
| `k3.1-pro` | Brigadier General (OF-6) | yes | 3T-class flagship, thinking-only (`reasoning_effort` low/high/max, default high, cannot be disabled), 1M. Image+video input (model table; live pixel test 2026-11-17 answered correctly). |
| `k3.1-pro-highspeed` | Brigadier General (OF-6) | no | Same model, ~2–3× speed, ~2× quota. Not deployed per the high-speed policy. |
| `k3` | Lieutenant Colonel (OF-5) | yes | 2.8T params / 104B active, natively multimodal (MoonViT-V2), 1M on Allegretto. Image+video input (model table; live pixel tests 2026-09 answered correctly). |
| `k3-256k` | Lieutenant Colonel (OF-5) | yes | Same model, 262K window, ~½ the quota of `k3`. Image-only input (model table; live `GET /coding/v1/models`: `supports_image_in: true`). |
| `kimi-for-coding` | Major (OF-4) | yes | K2.8 Preview — performance close to K3, 1M. `reasoning_effort` default `max`. Image+video input (model table; live `GET /coding/v1/models`: `supports_image_in: true`; third-party pixel tests answered correctly — the earlier "endpoint does not decode" finding is superseded, see Vision verification). |
| `kimi-for-coding-highspeed` | Major (OF-4) | no | K2.7 Code HighSpeed: same coding ability, ~5–6× speed, ~3× quota, 262K. Not deployed per the high-speed policy. |

### DeepSeek API (`https://api.deepseek.com`, pay-per-token)

Official pricing page (2026-11-21): both models 1M ctx / 384K (393,216) out; peak hours Mon–Fri 01:00–04:00 + 06:00–10:00 UTC **excluding Chinese public holidays**; concurrency 2,500/500.

| Model ID | Rank | Deployed | Notes |
|---|---|---|---|
| `deepseek-flash` (serves DeepSeek-V4.1-Flash-1017) | Captain (OF-2) | yes | 1M ctx, 384K (393,216) out, image input, thinking + non-thinking (default thinking), $0.15/$0.60 off-peak. Legacy ids `deepseek-v4-flash` / `deepseek-v4-flash-vision-exp` route here and bill Flash prices. Vision slot: `captain-v`. |
| `deepseek-v4-pro` (serves DeepSeek-V4-Pro-0813) | Captain Commandant (OF-3), also a Major order-3 deployment | yes | 1.6T params, 1M ctx, 384K (393,216) out, text-only, hardest reasoning / best agentic knowledge, $0.66/$1.98 off-peak. |

### Hetzner Inference (`https://inference.hetzner.com/v1`, free while the experiment runs)

The official docs list the base URL as `https://inference.hetzner.com/api/v1`; the 2026-11-21 live probe found **both** `/v1` (used by the deployments) and `/api/v1` answering (401 without a key). Rate limits per key: 4M input / 100K output tokens, 10 requests per 60s window.

Four ids over two serving deployments, all `max_model_len` 262144, all accepting images:

| Model ID | Rank | Deployed | Notes |
|---|---|---|---|
| `Qwen/Qwen3.6-35B-A3B` | Warrant Officer (OR-8) | yes (explicit id) | 35B total / 3B active MoE, served from the FP8 weights — alias of the FP8 id. |
| `Qwen/Qwen3.6-35B-A3B-FP8` | Warrant Officer (OR-8) | yes (explicit id + rank primary) | `warrant-officer`'s primary deployment. Natively multimodal (verified). |
| `Qwen/Qwen3.8-27B` | Second Lieutenant (OF-1a) | yes (explicit id) | Dense 27B — alias of the bare id. |
| `Qwen3.8-27B` | Second Lieutenant (OF-1a) | yes (explicit id + rank) | 28 tok/s. Also accepts images (verified). |

### Local models (Unsloth Studio, Strata)

| Model | Rank | Purpose |
|---|---|---|
| `unsloth/NVIDIA-Nemotron-3.5-Bolt-E4B-GGUF` | Sergeant (OR-4) | Fast executor (local). |
| `unsloth/Qwen3.6-35B-A3B-MTP-GGUF` | Warrant Officer (OR-8) local deployment | Local fallback of the cloud primary; the `-v` slot also uses it. |
| `swift-1.5-iq3_xxs` (Swift 1.5, via Strata) | Lieutenant (OF-1b) | The default model; the `-v` slot uses it too. |
## Proxy names (LiteLLM model names)

### Rank names (one name per rank; deployments ordered subscription → pay-per-token → free cloud → local)

| Rank | Proxy name | Deployments (model @ backend, order) | Context | Notes |
|---|---|---|---|---|
| Sergeant (OR-4) | `sergeant` | `unsloth/NVIDIA-Nemotron-3.5-Bolt-E4B-GGUF` @ Unsloth Studio | 128256 | `temperature: 0.1`, explicit-only (different Studio model). |
| Warrant Officer (OR-8) | `warrant-officer` | 1: `Qwen/Qwen3.6-35B-A3B-FP8` @ Hetzner · 2: `unsloth/...-MTP-GGUF` @ Studio | 262144 / 131072 | same model; free-cloud primary, local fallback. |
| Warrant Officer (vision) | `warrant-officer-v` | same deployments as `warrant-officer` | 262144 / 131072 | the `-v` slot carries vision (both verified). |
| Second Lieutenant (OF-1a) | `second-lieutenant` | `Qwen3.8-27B` @ Hetzner | 262144 | free cloud. |
| Lieutenant (OF-1b) | `lieutenant` | `swift-1.5-iq3_xxs` @ Strata | 131072 | **default**; `max_parallel_requests: 1`; 131072 is the window the engine serves (`--max-context`, live `n_ctx`), not the model's native 384K. |
| Lieutenant (vision) | `lieutenant-v` | same deployment as `lieutenant` | 131072 | the `-v` slot carries vision (verified). |
| Captain (OF-2) | `captain` | `deepseek-flash` @ DeepSeek | 1048576 | pay-per-token, explicit; cost-mapped. |
| Captain (vision) | `captain-v` | `deepseek-flash` @ DeepSeek | 1048576 | image input per `GET /v1/models`. |
| Captain Commandant (OF-3) | `captain-commandant` | 1: `glm-5-turbo` @ Z.ai · 2: `deepseek-v4-pro` @ DeepSeek | 200000 / 1048576 | subscription first; both text-only (no `-v`). |
| Major (OF-4) | `major` | 1: `kimi-for-coding` @ Kimi · 2: `glm-5.3-flash` @ Z.ai · 3: `deepseek-v4-pro` @ DeepSeek | 1048576 / 1000000 / 1048576 | text-only by contract (all three deployments are image-capable; images are addressed to major-v); quota-exhausted Kimi falls to Z.ai, then cash. |
| Major (vision) | `major-v` | 1: `kimi-for-coding` @ Kimi · 2: `glm-5.3-flash` @ Z.ai | 1048576 / 1000000 | K2.8 per docs + live endpoint metadata (see Vision verification); glm-5.3-flash is the 3×-quota fallback. |
| Lieutenant Colonel (OF-5) | `lieutenant-colonel` | 1: `glm-5.3` @ Z.ai · 2: `k3` @ Kimi · 3: `k3-256k` @ Kimi | 1000000 / 1048576 / 262144 | the pre-call context check drops the 262K row above 262K. |
| Lieutenant Colonel (vision) | `lieutenant-colonel-v` | 1: `k3` @ Kimi · 2: `k3-256k` @ Kimi | 1048576 / 262144 | `glm-5.3` absent (text-only model). |
| Brigadier General (OF-6) | `brigadier-general` | `k3.1-pro` @ Kimi | 1048576 | thinking-only; proxy pins `reasoning_effort: high`. |
| Brigadier General (vision) | `brigadier-general-v` | `k3.1-pro` @ Kimi | 1048576 | model table image+video; live pixel test 2026-11-17 answered correctly (see Vision verification). |

### Explicit model names (one name per ranked model, spelled like the upstream id)

| Proxy name | Backend | Rank it belongs to |
|---|---|---|
| `k3.1-pro` | Kimi | Brigadier General |
| `k3` | Kimi | Lieutenant Colonel |
| `k3-256k` | Kimi | Lieutenant Colonel |
| `kimi-for-coding` | Kimi | Major |
| `glm-5.3` | Z.ai Coding Plan | Lieutenant Colonel |
| `glm-5.3-flash` | Z.ai Coding Plan | Major |
| `glm-5-turbo` | Z.ai Coding Plan | Captain Commandant |
| `deepseek-flash` | DeepSeek API | Captain |
| `deepseek-v4-pro` | DeepSeek API | Captain Commandant (and Major order 3) |
| `Qwen/Qwen3.6-35B-A3B` · `Qwen/Qwen3.6-35B-A3B-FP8` | Hetzner | Warrant Officer |
| `Qwen/Qwen3.8-27B` · `Qwen3.8-27B` | Hetzner | Second Lieutenant |

Explicit names are single-deployment: one name = exactly one provider's deployment, no intra-name failover, no cross-rank fallback in or out. Asking for the id means asking for that model on that provider.

**Unranked pay-as-you-go (CheaperInference only; explicit selection).** `deepseek-v4.1-flash`, `gpt-5.6-luna`, `claude-sonnet-5.5`, `claude-opus-5.5`, and `glm-5.3-payg` (the cash twin of the Coding Plan's `glm-5.3` — named `-payg` so a call site can never mistake per-token billing for subscription quota). `gpt-5.6-sol` and `claude-fable-5` exist in the reseller catalogue as frontier options but have no deployment; add one when a task needs it.

## Vision verification

Every deployment behind a `-v` name (or carrying `attachment = true`) must actually see images:

- **Verified by repo pixel-color tests (1×1 red/blue):** `warrant-officer` / `warrant-officer-v` (Hetzner FP8 and the local GGUF), `second-lieutenant` (Qwen3.8-27B), `lieutenant` / `lieutenant-v` (Swift 1.5 on Strata).
- **Verified by official docs + live endpoint metadata (Kimi K2.8 / K3 / K3.1 Pro line):** `kimi-for-coding` (image+video), `k3` (image+video), `k3-256k` (image only), `k3.1-pro` (image+video). Kimi's model table declares image (+video) input for all of them, the live `GET /coding/v1/models` reports `supports_image_in: true`, and independent third-party pixel tests against this exact endpoint (hermes-agent #18990 / PR #18999, 2026-09 and 2026-11) answered a 1×1 pixel correctly.
  - **Format caveat (Kimi docs):** image parts must be content-array `image_url` entries with a base64 data URL; a public image URL is rejected (400 "unsupported image url").
  - The repo's earlier "Kimi coding endpoint answered black" finding is **superseded**: the image had been embedded as base64 in a plain text string, which the model correctly reported as no image. Sent as a proper `image_url` part, the coding endpoint decodes it. (Kimi also recommends its native APIs for K3.1 Pro — protocol translation through a proxy may vary model behavior.)
  - **TODO(vision-verify, repo-side):** re-run the pixel test THROUGH the proxy on server-nike to confirm LiteLLM's passthrough preserves the image part:

    ```sh
    KEY=$(cat ~/.config/opencode/keys/litellm-proxy.key)
    # 1x1 solid-red PNG, base64-encoded inline (no file needed)
    PNG_B64=$(python3 -c "
    import base64, zlib, struct
    def chunk(t, d):
        c = t + d
        return struct.pack('>I', len(d)) + c + struct.pack('>I', zlib.crc32(c))
    ihdr = struct.pack('>IIBBBBB', 1, 1, 8, 2, 0, 0, 0)
    idat = zlib.compress(b'\x00\xff\x00\x00')
    png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', ihdr) + chunk(b'IDAT', idat) + chunk(b'IEND', b'')
    print(base64.b64encode(png).decode())")
    curl -s http://server-nike.bee-blues.ts.net:4000/v1/chat/completions \
      -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
      -d "{\"model\":\"k3\",\"max_tokens\":20,\"messages\":[{\"role\":\"user\",\"content\":[
            {\"type\":\"text\",\"text\":\"What color is this image? One word.\"},
            {\"type\":\"image_url\",\"image_url\":{\"url\":\"data:image/png;base64,$PNG_B64\"}}
          ]}]}"
    ```

    Expected: `red`. Repeat with `"major-v"` and `"k3.1-pro"` (via their `-v`/explicit names) to cover the remaining Kimi rows.
- **Provider spec (DeepSeek/Z.ai):** `deepseek-flash` lists `input_modalities: [text, image]` in `GET /v1/models`; GLM-5.3-Flash is Z.ai's documented multimodal line (video/image/text/file input).

No fallback is ever added to a `-v` rank on the strength of an unverified flag: a vision request to an unverified `-v` name is fine (it stays on that one deployment), but auto-cascades only cross verified ranks.

## Pay-as-you-go (unranked)

The CheaperInference pool is the only unranked pool. Accessed by **explicit selection, never auto-fallback**; tiers are **cost-ordered (cheapest first)**, not capability-ordered. It spans from below to above the frontier rank and occupies general-officer slots only when a model is promoted to standing use.

| Tier | Models | Provider | Notes |
|---|---|---|---|
| 1 | `deepseek-v4.1-flash` | CheaperInference | Same model as Captain's `deepseek-flash`, 56% off list ($0.07/$0.26). |
| 2 | `gpt-5.6-luna` | CheaperInference | 1.1M ctx, OpenAI. $0.08/$0.48 via CI. |
| 2 | `claude-sonnet-5.5` | CheaperInference | Anthropic. $1.67/$8.35 via CI (17% off list). |
| 3 | `claude-opus-5.5` | CheaperInference | Anthropic. $2.60/$13.00 via CI (35% off list). |
| 3 | `glm-5.3-payg` | CheaperInference | Per-token twin of the Coding Plan's `glm-5.3`. |
| 4 | `gpt-5.6-sol` · `claude-fable-5` | CheaperInference | OpenAI / Anthropic flagships; no deployment yet. |

## Fallback Strategy

The lieutenant is the default. When it fails (Strata busy, overloaded, or not reachable) — **or when the prompt no longer fits its 128K window** — the request cascades down through the free-cloud/local stack:

```
lieutenant (local, deep reasoning)
  ↓ fail
second-lieutenant (Hetzner, free cloud)
  ↓ fail
warrant-officer (Hetzner primary → local Studio fallback)
  ↓ stop — sergeant is explicit-only
[paid ranks + every explicit model id — explicit selection only]
```

**A long prompt leaves the local rank by itself.** The `lieutenant` deployment's `max_input_tokens` is 131072 — the window the Strata engine serves on laptop-p16 — so LiteLLM's pre-call context check drops that deployment once the prompt exceeds 128K and the request goes to `second-lieutenant` (262K @ Hetzner). The ladder's long-context tier is the free cloud; the local rank is the deep-reasoning default.

Intra-rank deployment failover (order tiers within one name) is handled by LiteLLM under the same model name — e.g. `major` Kimi → Z.ai → DeepSeek, or `warrant-officer` cloud → local. `router_settings.fallbacks` only crosses ranks, and only downward through the free stack:

```yaml
router_settings:
  fallbacks:
    - lieutenant: [second-lieutenant, warrant-officer]
    - second-lieutenant: [warrant-officer]
    - lieutenant-v: [warrant-officer-v]   # vision cascade stays inside -v ranks
  max_fallbacks: 2
  # sergeant, all paid ranks, all explicit model ids: explicit-only, no fallback in or out
```

**No fallback between paid ranks** — `captain`, `captain-v`, `captain-commandant`, `major`, `major-v`, `lieutenant-colonel`, `lieutenant-colonel-v`, `brigadier-general`, `brigadier-general-v` are explicit selections. Auto-fallback across them would silently escalate cost, and circular fallbacks are unreliable in LiteLLM (it does not retry 4xx errors, and warns against cycles).

**Vision routing is client-side, and the proxy does no vision filtering.** opencode (and pi) only send images to names marked attachment-capable — the `-v` ranks and the attachment-flagged explicit ids (`kimi-for-coding`, `k3`, `k3-256k`, `k3.1-pro`, `glm-5.3-flash`, `deepseek-flash`). The plain `major` rank is **not** in that list (text-only by contract), so an image never lands on a plain rank. (LiteLLM 1.86.0 does **not** filter vision-incapable deployments out pre-call — no such check exists — so every deployment behind a `-v` name is image-capable per the verification above, and the client gates the modality.)

Paid escalation is handled outside LiteLLM's automatic fallback chain — it is triggered when the user explicitly selects a paid rank or id, or when a higher-level orchestrator decides to escalate.

## High-speed models: existence and why we don't use them

High-speed variants exist across the ranked subscriptions but **we don't deploy them**. They are mapped to the rank of their standard twin (see the complete mapping) so the ladder stays complete:

| Provider | Standard model (deployed) | High-speed variant (documented, not deployed) | Cost difference |
|---|---|---|---|
| **Z.ai** | `glm-5.3`, `glm-5.3-flash` | `glm-5.3-highspeed`, `glm-5.2-highspeed` (plan), `glm-5.3-flashx` / `glm-5.3-flashx-legal` (Standard API only) | Same model on faster GPU; flashx not on the plan. |
| **Kimi** | `k3.1-pro`, `kimi-for-coding` | `k3.1-pro-highspeed`, `kimi-for-coding-highspeed` | ~2× quota (K3.1), ~3× quota / ~6× speed (K2.7 HS). Same weights, same quality. |
| **DeepSeek** | `deepseek-flash` | none — V4.1 Flash is the fast default | N/A. |
| **Hetzner** | all four ids | none | Already the fast option. |

Decision (unchanged): the standard id on every subscription — same output, lower quota cost, and agent work doesn't care about streaming latency.
