# AI Ranks — Belgian Air Component

All rank names in English, using the Belgian Air Component (Luchtcomponent / Force aérienne) structure. The complete hierarchy provides room for many models to be slotted in without saturation.

**A rank name is a pure abstraction over the model currently holding the slot.** It never contains a model name, provider name, or implementation detail (dense/sparse, quant, backend). The only permitted suffix is a *feature* suffix — currently `-v` for the vision-capable model of a rank. **Multiple models may share one rank**; in the proxy they are multiple deployments under a single model name (primary + redundant/failover).

**The ladder covers the standing stack — local + subscription models.** The pay-as-you-go pool sits *outside* the ladder (explicit escalation, cost-ordered tiers); it currently includes models at and above frontier-rank capability. General officer ranks are reserved for paid models promoted to standing use. The size bands on empty slots are approximate and written for dense models; MoE models are slotted by capability (active params + knowledge capacity), not total params.

Research date: 2026-11-20

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
| OR-8 | **Warrant Officer** | `unsloth/Qwen3.6-35B-A3B-MTP-GGUF` (local) · `Qwen/Qwen3.6-35B-A3B-FP8` (cloud) | Unsloth Studio + Hetzner (free cloud) | Workhorse. One rank, two deployments of the same model — local primary, cloud redundant. |
| OR-9 | **Chief Warrant Officer** | | | Reserved. |

## Junior Officers (OF-1a to OF-2)

| NATO | English | Model | Source | Purpose |
|---|---|---|---|---|
| OF-1a | **Second Lieutenant** | `Qwen3.8-27B` | Hetzner Inference (free cloud) | The 27B base model of Swift 1.5 (same architecture, minus post-training). Cleaner output, ~28 tok/s. |
| OF-1b | **Lieutenant** | `swift-1.5-iq3_xxs` | Strata (local) | **Default model.** Deep reasoning, 384K context. Smart, reliable, delegates to lower ranks. |
| OF-2 | **Captain** | | | Reserved. |

## Senior Officers (OF-3 to OF-5)

| NATO | English | Model | Source | Purpose |
|---|---|---|---|---|
| OF-3 | **Captain Commandant** | | | Reserved. |
| OF-4 | **Major** | `kimi-for-coding` (K2.8 Preview) | Kimi Code subscription | Previous-generation Kimi — "approaches K3" but a generation below the frontier. Explicit selection only, not in the auto-fallback chain. |
| OF-5 | **Lieutenant Colonel** | `glm-5.3` | Z.ai Coding Plan | Dense flagship, full reasoning, token-efficient per token vs Opus. Text-only. Credit mult: 6.9/1.7/24. |
| OF-5 | **Lieutenant Colonel** (vision) | `k3` | Kimi Code subscription | 2.8T params / 104B active, **natively multimodal** (MoonViT-V2), 1M ctx. Strongest open-weight in the stack; ties GLM-5.3 on the Intelligence Index, trails it on SWE-bench Verified (93.4 vs 95.4). |
| OF-5 | **Lieutenant Colonel** (vision) | `k3-256k` | Kimi Code subscription | Same model, 256K window. ~½ the quota of the 1M variant. |
| OF-5 | **Lieutenant Colonel** (vision) | `glm-5.3-flash` | Z.ai Coding Plan | Sparse MoE multimodal, 3× quota, cheaper credits. Credit mult: 2.3/0.56/8. |

## General Officers (OF-6 to OF-9)

| NATO | English | Model | Source | Purpose |
|---|---|---|---|---|
| OF-6 | **Brigadier General** | | | Reserved: paid model promoted to standing use. |
| OF-7 | **Major General** | | | Reserved: paid model promoted to standing use. |
| OF-8 | **Lieutenant General** | | | Reserved: paid model promoted to standing use. |
| OF-9 | **General** | | | Reserved: paid model promoted to standing use. |

## Proxy names (LiteLLM model names)

| Rank | Proxy name | Deployments (model @ backend) |
|---|---|---|
| Sergeant (OR-4) | `sergeant` | `unsloth/NVIDIA-Nemotron-3.5-Bolt-E4B-GGUF` @ Unsloth Studio (server-nike) |
| Warrant Officer (OR-8) | `warrant-officer` | `unsloth/Qwen3.6-35B-A3B-MTP-GGUF` @ Unsloth Studio (primary) · `Qwen/Qwen3.6-35B-A3B-FP8` @ Hetzner (cloud) |
| Second Lieutenant (OF-1a) | `second-lieutenant` | `Qwen3.8-27B` @ Hetzner (free cloud) |
| Lieutenant (OF-1b) | `lieutenant` | `swift-1.5-iq3_xxs` @ Strata (laptop-p16) |
| Major (OF-4) | `major` | `kimi-for-coding` (K2.8) @ Kimi — previous generation |
| Lieutenant Colonel (OF-5) | `lieutenant-colonel` | `glm-5.3` @ Z.ai — text deployment |
| Lieutenant Colonel, vision (OF-5) | `lieutenant-colonel-v` | `k3` @ Kimi · `k3-256k` @ Kimi · `glm-5.3-flash` @ Z.ai — natively multimodal deployments |

**Unranked models are named by model id** — the rank abstraction does not apply to them: `deepseek-flash`, `deepseek-v4-pro`, `deepseek-v4.1-flash`, `gpt-5.6-luna`, `claude-sonnet-5.5`, `claude-opus-5.5`, `glm-5.3` (pay-as-you-go escalation, explicit selection only).

Local Studio utilities are not part of the client table anymore. Only the three local models behind the standing ladder — Nemotron (sergeant), Qwen3.6-35B-A3B (warrant-officer) and Swift 1.5 (lieutenant, via Strata) — are kept; add another local model only when a task needs it.

## Pay-as-you-go (unassigned in rank structure)

These are accessed only by **explicit selection, never auto-fallback**. Tiers are **cost-ordered (cheapest first), not capability-ordered** — the pool spans from below to above the frontier rank. They occupy rank slots (general officer) only when promoted to standing use.

| Tier | Models | Provider | Notes |
|---|---|---|---|
| Escalation 1 | `deepseek-flash` (V4.1 Flash 1017) | DeepSeek API | 1M ctx, vision, $0.15/$0.60 off-peak. Default pay tier. |
| Escalation 1 | `deepseek-v4-pro` | DeepSeek API | 1.6T params, best agentic knowledge. $0.66/$1.98 off-peak. |
| Escalation 2 | `gpt-5.6-luna` | CheaperInference | 1.1M ctx, OpenAI. $0.08/$0.48 via CI. |
| Escalation 2 | `claude-sonnet-5.5` | CheaperInference | Anthropic. $1.67/$8.35 via CI (17% off list). |
| Escalation 3 | `claude-opus-5.5` | CheaperInference | Anthropic. $2.60/$13.00 via CI (35% off list). |
| Escalation 3 | `kimi-k3` (pay-as-you-go) | Kimi API | 2.8T params, $3/$15 per 1M tokens. |
| Escalation 4 | `gpt-5.6-sol` | CheaperInference | OpenAI flagship. |
| Escalation 4 | `claude-fable-5` | CheaperInference | Anthropic flagship. |

## Subscription model details

### Z.ai Coding Plan (subscription, NOT pay-per-token)

**Endpoint:** `https://api.z.ai/api/coding/paas/v4`
**Key:** `zai.key` (from agenix secret)

| Model ID | Description | Context | Output | Notes |
|---|---|---|---|---|
| `glm-5.3` | Dense 92-layer flagship | 1M | 131K | Token-efficient, beats Opus 4.8 per token. Credit mult: 6.9/1.7/24. |
| `glm-5.3-flash` | Sparse MoE (18B active), multimodal | 1M | 131K | 3× quota, cheaper credits. Credit mult: 2.3/0.56/8. |

**No high-speed variant on the plan.** `glm-5.3-highspeed` and `glm-5.3-flashx` exist only on the pay-per-token Standard API (separate key). They are the same model served on faster GPU infrastructure — not part of any subscription. We don't need high-speed models; both our models are fast enough for interactive use.

**Note:** Legacy model IDs `glm-5.2` and `glm-5.1` are auto-routed to `glm-5.3`; `glm-4.7` is auto-routed to `glm-5.3-flash`. They consume the same credits as their target models.

**Off-peak:** 50% credit rate (weekends + non-peak hours, Mon–Fri 14:00–18:00 SGT).

### Kimi Code (subscription, membership tiers)

**Endpoint:** `https://api.kimi.com/coding/v1`
**Key:** `kimi.key` (from agenix secret)

| Model ID | Description | Context | Availability |
|---|---|---|---|
| `k3.1-pro` | K3.1 Pro — 3T-class, thinking-only | 1M (Pro+) | Plus+ |
| `k3.1-pro-highspeed` | Same as K3.1 Pro, 2–3× speed, 2× quota | 1M | Pro+ |
| `k3` | K3 — 2.8T params / 104B active, natively multimodal, previous flagship | 1M (Pro+) | Plus+ |
| `k3-256k` | K3, 256K context, cheaper quota | 262K | Plus+ |
| `kimi-for-coding` | K2.8 Preview — approaches K3 | 1M | Plus+ |
| `kimi-for-coding-highspeed` | K2.7 Code HighSpeed, 5–6× speed | 262K | Pro+ |

**Note:** K3.1 Pro requires `reasoning_effort: low/high/max` — thinking cannot be disabled.

**No high-speed models needed across any subscription.** The `highspeed` variants (`k3.1-pro-highspeed`, `kimi-for-coding-highspeed`, Z.ai's `glm-5.3-highspeed`) exist as faster-served versions of the same models — same weights, same quality, delivered on faster GPU infrastructure. They consume more quota per token (2× for Kimi, pay-per-token pricing for Z.ai) but produce identical output. We prefer the standard variants: they are fast enough for interactive use and cost less quota per token.

### DeepSeek API (pay-as-you-go)

**Endpoint:** `https://api.deepseek.com`
**Key:** `deepseek.key` (from agenix secret)

| Model ID | Description | Context | Output | Off-peak price | Peak price |
|---|---|---|---|---|---|
| `deepseek-flash` | V4.1 Flash 1017, vision, fastest | 1M | 384K | $0.15/$0.60 | $0.30/$1.20 |
| `deepseek-v4-pro` | V4 Pro, 1.6T params, hardest reasoning | 1M | 384K | $0.66/$1.98 | $1.32/$3.96 |

Peak hours: 01:00–04:00 UTC and 06:00–10:00 UTC, Mon–Fri. Everything else off-peak.

### Hetzner Inference (free, experimental)

**Endpoint:** `https://inference.hetzner.com/v1`
**Key:** `hetzner.key` (from agenix secret)

| Model ID | Description | Context | Notes |
|---|---|---|---|
| `Qwen/Qwen3.6-35B-A3B-FP8` | 35B total / 3B active, MoE | 262K | 175 tok/s aggregate, ~1.5s TTFT |
| `Qwen3.8-27B` | Dense 27B, cleaner German | 262K | 28 tok/s — fine for short agentic turns (second-lieutenant fallback), not for long-form generation |

### CheaperInference (wallet-backed, discounted marketplace)

**Endpoint:** `https://api.cheaperinference.com/v1`
**Key:** `cheaperinference.key` (from agenix secret)

Key models available at 17–60% off list:
- `gpt-5.6-luna` — $0.08/$0.48 (60% off)
- `claude-sonnet-5.5` — $1.67/$8.35 (17% off)
- `claude-opus-5.5` — $2.60/$13.00 (35% off)
- `deepseek-v4.1-flash-1017` — $0.07/$0.26 (56% off)

## Fallback Strategy

The lieutenant is the default. When it fails (Strata busy, overloaded, or not reachable), the request cascades down through the local + free-cloud stack. The automatic cascade stops at sergeant; paid escalation is always an explicit model selection:

```
lieutenant (local, deep reasoning)
  ↓ fail
second-lieutenant (Hetzner, free cloud)
  ↓ fail
warrant-officer (local + cloud workhorse)
  ↓ fail
sergeant (local, fast exec)
  ↓ stop — no automatic paid escalation
[paid tiers — explicit selection only]
```

Intra-rank deployment failover (e.g. warrant-officer local → cloud) is handled by LiteLLM itself under the same model name; `router_settings.fallbacks` only crosses ranks — and only downward through the local stack:

```yaml
router_settings:
  fallbacks:
    - lieutenant: [second-lieutenant, warrant-officer, sergeant]
    - second-lieutenant: [warrant-officer, sergeant]
    - warrant-officer: [sergeant]
  max_fallbacks: 3
  # sergeant: last local option — escalation to paid models is explicit
```

**No fallback between paid ranks** — `major`, `lieutenant-colonel`, and `lieutenant-colonel-v` are explicit selections. Auto-fallback across them would silently escalate cost, and circular fallbacks are unreliable in LiteLLM (it does not retry 4xx errors, and warns against cycles).

**Vision routing is client-side:** opencode only sends images to models marked attachment-capable — `lieutenant-colonel-v` and `deepseek-flash`. An image therefore never lands on a text-only deployment, no fallback needed.

Paid escalation is handled outside LiteLLM's automatic fallback chain — it's triggered when the user explicitly selects a paid model name, or when a higher-level orchestrator decides to escalate.

## High-speed models: existence and why we don't use them

High-speed (`-highspeed`) variants exist across all three of our subscription providers, but **we don't need them**. Here's the complete picture:

| Provider | Standard model | High-speed variant | What it is | Cost difference |
|---|---|---|---|---|
| **Z.ai** | `glm-5.3`, `glm-5.3-flash` | `glm-5.3-highspeed`, `glm-5.3-flashx` | Same model on faster GPU | Pay-per-token only; not on subscription. Standard models on the plan are fast enough. |
| **Kimi** | `k3.1-pro`, `kimi-for-coding` | `k3.1-pro-highspeed`, `kimi-for-coding-highspeed` | Same model, faster GPU delivery | 2× quota for K3.1, 3× quota for K2.7 HS. Same weights, same quality. |
| **DeepSeek** | `deepseek-v4-pro` | None (V4.1 Flash is the fast default) | N/A | V4.1 Flash is already our fast default. |
| **Hetzner** | `Qwen3.6-35B-A3B` | None | N/A | Already the fast option. |
| **CheaperInference** | All models | None | N/A | N/A |

**Decision:** Use the standard model ID on every subscription. High-speed variants:
- Produce identical output (same model weights, same intelligence)
- Cost more quota per token (Kimi: 2–3× quota)
- Offer faster first-token / streaming (nice for human-facing UX, unnecessary for agent work)
- Z.ai's `highspeed`/`flashx` are pay-per-token-only and not part of any subscription

For agent-driven work (opencode, pi), the standard models are the right choice: same quality, lower quota cost, and the agent doesn't care about streaming latency.
