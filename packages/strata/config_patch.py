# The declarative engine policy for packages/strata/default.nix: rewrite every
# engine config under STRATA_HOME (strata-<model>.json) so the served model
# matches the module options, whatever `strata --setup` answered. Run from the
# `strata` wrapper, from `strata-server` and from the wrapped engine binary;
# it must stay idempotent (a rerun produces a byte-identical file, so the
# mtime ordering strata-server uses to pick the served model is not disturbed).
#
# Since Strata 0.2.0 a config carries the engine options twice:
#   "args"          what setup.py or the app generated;
#   "user_args"     the options a person set by hand, which serve/server.py
#                   merges OVER "args" at every start (strata_control/user_args.py);
#   "args_written"  the "args" setup last wrote, so a later setup run can tell
#                   the hand edits apart and carry them over.
# A policy that only wrote "args" would therefore be silently overridden by a
# leftover "user_args" entry (the app's settings form writes them). So this
# script writes the policy into "args", drops the policy-flagged options from
# "user_args" (the layer that wins) and stamps "args_written" as its own write,
# while keeping every option the person set that this module does not own.
#
# One exception: a config an older Strata wrote has no "args_written" at all, and
# setup.py then has its own rule for telling hand edits apart ("an option my new
# args do not have was added by hand"). This script leaves such a file without
# "args_written" rather than inventing it, because inventing it would mark those
# hand edits as generated - and the next `strata --setup` would drop them.
import glob, json, os, sys

ctx, kv, kv_res, rope, vram, pcie, spec, workers, affinity, adapt, tail, env_json, vision = (
    int(sys.argv[1]), sys.argv[2], int(sys.argv[3]), sys.argv[4], int(sys.argv[5]),
    sys.argv[6], sys.argv[7], sys.argv[8], sys.argv[9], sys.argv[10],
    sys.argv[11] == "true", sys.argv[12], sys.argv[13] == "true")
share = sys.argv[14]
env_patch = json.loads(env_json or "{}")
home = os.environ.get("STRATA_HOME") or os.path.expanduser("~/.local/share/strata")

# Upstream's own capture()/stamp()/groups(): the same code setup.py and the
# server use, so the two layers cannot drift apart (it is stdlib-only).
sys.path.insert(0, share)
from strata_control import user_args as UA

# The options this module owns. Each is (re)written into "args" below (or
# removed from it: --kv-resident for k8v4, the rope flags inside the trained
# context), so a copy in "user_args" would be a stale value that wins over the
# module options at engine start. Options the module leaves at null ("not set":
# the engine's own default) are NOT listed: a hand-set value is kept for those.
POLICY = {
    "--max-context", "--kv", "--kv-resident", "--rope-scaling", "--rope-scale",
    "--vram-reserve-mib", "--spec-min-p",
}
if pcie != "none":
    POLICY.add("--pcie-frac")
if workers != "none":
    POLICY.add("--pool-workers")
if affinity != "none":
    POLICY.add("--pool-affinity")
if adapt != "none":
    POLICY.add("--adapt-every")


def set_opt(args, flag, value):
    # Replace the flag's value in place when it is already correct (so a rerun
    # is byte-identical and the file is not rewritten), drop stale occurrences,
    # and append it when it is missing.
    out, i, found = [], 0, False
    while i < len(args):
        if args[i] == flag:
            cur = None
            i += 1
            if i < len(args) and not args[i].startswith("--"):
                cur = args[i]
                i += 1
            if value is not None and cur == str(value):
                found = True
                out += [flag, cur]
            continue
        out.append(args[i]); i += 1
    if value is not None and not found:
        out += [flag, str(value)]
    return out


failed = []
for p in sorted(glob.glob(os.path.join(home, "strata-*.json"))):
    if p.endswith(".shared-settings.json"):     # the web app's Chat settings, not a model
        continue
    try:
        with open(p, encoding="utf-8") as f:
            text = f.read()
        c = json.loads(text)
        if not isinstance(c, dict) or not isinstance(c.get("args"), list):
            continue
        a = c["args"]
        # The person's options, before this rewrite: "user_args" plus anything in
        # "args" that differs from "args_written" (a hand edit since the last
        # write). The policy flags are skipped: they are ours to set, and a
        # differing value is a stale one, not a choice to keep.
        mine = UA.capture(c, POLICY)
        mine = UA.flat([g for g in UA.groups(mine) if UA.flag_of(g) not in POLICY])
        # Mandatory for native packs (the engine refuses to start/serve
        # them without these); the settings form drops unknown flags, so
        # enforce them on every rewrite. "auto" is the value setup.py writes:
        # a bare flag would make the engine take the next option as its value.
        if "--expert-cache" not in a:
            a += ["--expert-cache", "auto"]
        # The module's draft-confidence floor. `--spec-min-p` is written ONCE with
        # its final value: writing it twice (a placeholder first, the real value
        # after) moved it to the end of the args even when it was already correct,
        # which rewrote every config once after an upgrade and bumped the mtimes
        # strata-server orders by. A module value of null ("none") keeps the flag
        # at 2, unreachable for a probability, i.e. the verify window is not
        # extended on a draft-confidence basis.
        a = set_opt(a, "--spec-min-p", 2 if spec == "none" else spec)
        if ctx > 0:
            a = set_opt(a, "--max-context", ctx)
        if kv:
            a = set_opt(a, "--kv", kv)
        # k8v4 never streams its KV (the engine refuses the combination)
        if kv == "k8v4" or kv_res <= 0:
            a = set_opt(a, "--kv-resident", None)
        else:
            a = set_opt(a, "--kv-resident", kv_res)
        # past the trained 262144 the angles must be rescaled; inside it,
        # keep the model completely stock (no rope flags at all)
        if ctx > 262144:
            a = set_opt(a, "--rope-scaling", rope)
            a = set_opt(a, "--rope-scale", f"{ctx / 262144:g}")
        else:
            a = set_opt(a, "--rope-scaling", None)
            a = set_opt(a, "--rope-scale", None)
        a = set_opt(a, "--vram-reserve-mib", vram)
        # Calibrated hardware knobs (tools/calibrate.py): set only when the
        # module provided them, otherwise the engine's default/probe stands.
        # (--spec-min-p is done above, with the other always-written options.)
        if pcie != "none":
            a = set_opt(a, "--pcie-frac", pcie)
        if workers != "none":
            a = set_opt(a, "--pool-workers", workers)
        if affinity != "none":
            a = set_opt(a, "--pool-affinity", affinity)
        if adapt != "none":
            a = set_opt(a, "--adapt-every", adapt)
        # Valueless flag: append when enabled (dedup), never touch args
        # when disabled - the engine's own default is off.
        if tail and "--prompt-cache-tail" not in a:
            a.append("--prompt-cache-tail")
        # Merge the module's engine environment (flags with no command-line
        # form), keeping anything setup.py or the user already set.
        if env_patch:
            c["env"] = {**(c.get("env") or {}), **{k: str(v) for k, v in env_patch.items()}}
        # Images follow the package's vision build, not a stale config
        # block: a config written by an older install (or by setup with
        # --vision yes) keeps a "vision" block pointing at
        # engine/strata-vision, which a vision=false build does not ship.
        # The server would then try to start it and fail model loads
        # ("vision encoder failed to start ... engine/strata-vision").
        if not vision:
            c.pop("vision", None)
        c["args"] = a
        # Record this rewrite as the writer of record: "args_written" = what is
        # in "args" now (so setup.py does not read the policy flags as hand
        # edits), "user_args" = the person's options still standing.
        had_written = UA.WRITTEN_KEY in c
        UA.stamp(c, mine)
        if not had_written:
            # But do NOT invent "args_written" for a config an older Strata
            # wrote without one: a flag there that setup.py's new args do not
            # have is a hand edit (-adapt-swaps, -adapt-decay, ...), and setup's
            # own rule for such a file carries it into "user_args" on its next
            # run. Stamping it here would mark those as generated and drop them.
            c.pop(UA.WRITTEN_KEY, None)
        new_text = json.dumps(c, indent=1)
        # Skip unchanged files: strata-server picks the served model by
        # mtime, so rewriting everything would destroy that ordering.
        if new_text == text:
            continue
        # Atomic replace so a concurrent reader never sees a partial file.
        tmp = p + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            f.write(new_text)
        os.replace(tmp, p)
    except Exception as e:
        failed.append(f"{p}: {e}")
if failed:
    for msg in failed:
        print(f"strata: could not patch {msg}", file=sys.stderr)
    # This script is the enforcement point of the module policy: do not
    # fail open with stale settings.
    sys.exit(1)
