# Prompt: migrate a repo's agent models onto the rank ladder

Paste into an opencode session at the root of the target repo. Replace
`<target repo>` references as needed. The rank gateway (LiteLLM,
`server-nike:4000`) and `~/code/nixos-config/docs/ai-ranks.md` are the
source of truth for the ladder; this prompt is the repo-side work.

---

## Goal

Every agent model reference in this repo becomes a rank name
(`proxy/<rank>`). A rank is a pure abstraction over the model holding the
slot: model changes must never require touching client config, agent
frontmatter, or skill docs.

**Standing ladder (verify current state in `ai-ranks.md` before acting):**

| Rank | Backend class | Concurrency | Use |
|---|---|---|---|
| `proxy/sergeant` | local (Unsloth Studio) | **single-slot — sequential only** | mechanical, build-verified, faithful execution |
| `proxy/warrant-officer` | free cloud (Hetzner) + local fallback | **parallel-safe** | workhorse volume, generation, fix loops, **all parallel fan-out** |
| `proxy/second-lieutenant` | free cloud (Hetzner) | parallel-safe | clean-output language judgment |
| `proxy/lieutenant` | local (Strata) | **single-slot — sequential only** | deep reasoning, judgment, main session |
| `proxy/*-v` | siblings of the ranks above, same model | as parent rank | **the only vision slots** |
| higher ranks (`captain` and up: `captain*`, `captain-commandant`, `major*`, `lieutenant-colonel*`, `brigadier-general*`, plus every explicit model id) | paid | — | explicit per-task escalation only, never an agent default |

**Hard contracts (do not violate):**

1. Plain ranks are text-only by contract, even when their model is
   natively multimodal. Vision is exposed only through the `-v` sibling.
   Consequence: the model behind a plain rank can be swapped freely;
   nobody expects vision from it.
2. Local ranks (single-slot backends) take sequential traffic only. A
   parallel fan-out on a local rank queues, and queued requests can
   time out. Parallel work goes to cloud ranks.
3. No agent defaults to a rank above `lieutenant`.
4. Provider-specific options (`thinking`, `reasoning_effort`, provider
   quirks) do not appear in client config — the proxy owns model
   behaviour parameters.

---

## Step 0 — Read the ladder

1. Read `~/code/nixos-config/docs/ai-ranks.md` and
   `docs/litellm-proxy-design.md` (committed state + working tree).
2. Record per rank: capability tier, context limit, cost, backend
   concurrency (single-slot vs parallel-safe), modality.
3. Note which `-v` siblings exist. If a rank's model is vision-capable
   but no `-v` sibling exists, flag it — the contract requires one.
4. Read the target repo's `git status` first. Foreign WIP in the tree
   means: edit additively, never commit foreign hunks, report at the end.

## Step 1 — Audit every model reference

```
grep -rIn --exclude-dir=.git -i -e deepseek -e kimi -e zai -e glm -e hetzner \
     -e anthropic -e claude -e openai -e unsloth -e strata -e <provider-ids> .
```

Classify every hit:

| Class | Action |
|---|---|
| Live agent config (opencode.json/c, agent `.md` frontmatter) | remap (Step 3) |
| Skill / pipeline docs naming an agent's model | rewrite to rank (Step 4) |
| Rules/context files with tier descriptions | rewrite (Step 4) |
| Historical records (`ops/` plans, research logs, brainstorms, Literature notes) | **do not edit** |
| Document content (`src/`) | **do not edit** (watch false positives: "Ha**kimi**", "deep **seek**") |

Verify every provider referenced in live config still exists in the
client config (`~/code/nixos-config/users/opencode.nix`). A reference to
a provider the client no longer ships is a dead reference — remapping
repairs it, so note how many existed before the fix.

## Step 2 — Classify each agent (two axes)

For every agent, decide the rank from two independent axes.

**Axis 1 — capability (what the work demands):**

| Work class | Rank |
|---|---|
| Mechanical: checkers, scanners, runners, formatters, boilerplate, index building, faithful transformation, cheap bulk workers | `sergeant` |
| Volume: agentic pipelines, code generation and fix loops, long-form generation, structural operations (splits, inserts, linkers), research scanning | `warrant-officer` |
| Language quality: style, tone, translation, terminology, prose-pattern audits | `second-lieutenant` |
| Deep judgment: formal/proof verification, math, adversarial reasoning, domain-critical audits, medical/scientific analysis, model builders, high-stakes decisions | `lieutenant` |
| Reads rendered figures / images / PDFs | the `-v` sibling (validators & checkers → `warrant-officer-v`; deep visual judgment → `lieutenant-v`) |

Rule: the cheapest sufficient rank. When torn between two, take the lower
one and note it.

**Axis 2 — concurrency (how it is launched):**

Read the skills/workflows that delegate to the agent. Look for explicit
launch patterns: "parallel", "× N", "one per chapter/file", fan-out
phases.

- **Parallel fan-out (N > 1 at once) → `warrant-officer`, unconditionally.**
  This axis overrides Axis 1: a `sergeant`-class checker that runs in a
  parallel panel is a cloud-rank agent, because a local panel queues and
  times out.
- **Sequential single-instance → Axis 1 decides.**
- If a skill runs the same agent in both modes, the parallel membership
  wins (cloud rank works for sequential calls too; a local rank breaks
  the parallel one).
- If the launch pattern is unclear, list the affected agents and ask
  the user before defaulting.

Known pattern heuristics for this project family: review panels that
state "sequential" (e.g. 20-category biomedical review, 6-persona
adversarial review) are safe on `lieutenant`; review phases explicitly
marked "parallel" and per-item scan workers are not. Verify per skill —
do not assume.

## Step 3 — Apply the remap

1. **Main config** (`opencode.json` / `opencode.jsonc`):
   - each agent: `"model": "proxy/<rank>"`;
   - **delete provider-specific `options`** (`thinking`, `reasoning_effort`,
     provider quirks) from rank agents;
   - top level: `model` = `proxy/lieutenant` (main session),
     `small_model` = `proxy/sergeant` (sequential utilities).
2. **Agent frontmatter** (`.opencode/agents/*.md` or equivalent): mirror
   the config value exactly — frontmatter **overrides** config, so drift
   is a live bug. Files present in both must match byte-for-byte on the
   `model:` line. Frontmatter-only agents (no config entry) are governed
   by their frontmatter.
3. **Nix client config** (only when a rank's capability changed, e.g.
   adding a `-v` sibling), in `~/code/nixos-config/`:
   - `services/litellm-proxy.nix`: deployment `supports_vision` flags
     (`true` only on `-v`-rank deployments carrying a vision-capable
     model; `false` on plain ranks and on text-only fallbacks of `-v`
     ranks, with a comment); fallback lists: the vision cascade never
     leaves the `-v` ladder;
   - `users/opencode.nix`: `attachment = true` only on `-v` names and
     paid vision ids — never on plain ranks;
   - both files: `nix-instantiate --parse` must pass.
   - Never bundle the nixos change with a commit that also carries
     foreign WIP hunks; if the tree is dirty with other work, leave it
     uncommitted and report.
4. **Vision agents** land on the `-v` rank matching their capability
   axis, not on a paid frontier rank. Paid vision stays reserved.

## Step 4 — Rewrite the docs

- Tier descriptions in `AGENTS.md` / `CLAUDE.md` / config
  `instructions`: state the ladder, the two hard contracts (local =
  sequential; `-v` = vision), and the escalation rule (above-lieutenant
  = explicit per task).
- Every per-agent `**Model:**` mention in skill/pipeline docs → rank.
  Replace stale tier vocabulary (e.g. `haiku`/`sonnet`/`opus` cost
  labels) with ranks in the same pass.
- Rules files: cheapest-sufficient-model and security-model lines →
  ranks, including the parallel-fan-out clause.
- Historical records stay untouched (see Step 1).

## Step 5 — Verification gates (all must pass)

1. Config parses: `json.load` / `nix-instantiate --parse`.
2. Zero stale provider/model ids in live config (grep from Step 1,
   re-run on config + frontmatter + skills + context only).
3. Frontmatter ↔ config consistency: script-compare every `model:` line
   against the config map; zero mismatches.
4. No agent on a paid rank (no `captain`/`captain*`/`captain-commandant`/
   `major`/`major*`/`lieutenant-colonel*`/`brigadier-general*` or explicit
   paid model id in any default mapping).
5. **Parallel-set audit:** every agent a skill launches in N > 1 sits on
   a cloud rank. Cross-check the list against the skills' launch
   statements.
6. **Vision audit:** every image/figure-reading agent sits on a `-v`
   rank; no plain rank carries an `attachment` flag; every
   vision-capable rank has its `-v` sibling.
7. `git status` clean after committing; staged sets contained no foreign
   files (mandatory pre-commit check: `git diff --cached --name-only`).

## Step 6 — Commits

Logical groups, in order:

1. `config(agents): <remap summary>` — main config + frontmatter
   **together** (frontmatter overrides config; splitting strands a state).
2. `config(context,skills): <docs summary>` — rules + skill doc
   rewrites.
3. nixos side (if Step 3.3 applied): its own commit in that repo,
   excluding foreign WIP.

Imperative subjects, no "and", no generated or out-of-scope files, no
`git add -A`.

## Report

- Final distribution table (rank → agent count → role).
- Notable decisions: anything moved against its capability axis (parallel
  override), anything left on a lower rank than the user might expect
  (with the reason), vision assignments.
- Verification gate results, one line each.
- Uncommitted items and where they sit (e.g. foreign WIP in nixos).
