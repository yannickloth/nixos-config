# The declarative engine policy for packages/strata/default.nix: rewrite every
# engine config under STRATA_HOME (strata-<model>.json) on every engine start.
# It must stay idempotent (a rerun produces a byte-identical file, so the
# mtime ordering strata-server uses to pick the served model is not disturbed).
#
# The module owns exactly one option: --expert-cache. It is mandatory for
# native packs (the engine refuses to start/serve without it) and the web
# UI's settings form drops flags it does not know, so this script re-asserts
# it on every rewrite. "auto" is the value setup.py writes: a bare flag would
# make the engine take the next option as its value.
#
# Plus one package-correctness rule: a "vision" block points at
# engine/strata-vision, which THIS package ships only when it was built with
# the encoder (argv[2]). A config written by an older install (or by setup
# with --vision yes) keeps the block either way; from a build without the
# encoder the server would try to start the missing binary and fail every
# model load ("vision encoder failed to start ... engine/strata-vision"), so
# such a block is dropped. With the encoder shipped, the block is the
# person's setup answer and stays.
#
# Everything else - --max-context, the rope flags, --kv/--kv-resident,
# --vram-reserve-mib, --pcie-frac, --spec-min-p, --pool-workers,
# --pool-affinity, --adapt-every, --prompt-cache-tail - is left to
# `strata --setup` and the app's settings form at runtime: the script neither
# writes nor removes any of them, in "args" or in "user_args".
#
# Since Strata 0.2.0 a config carries the engine options twice:
#   "args"          what setup.py or the app generated;
#   "user_args"     the options a person set by hand, which serve/server.py
#                   merges OVER "args" at every start (strata_control/user_args.py);
#   "args_written"  the "args" setup last wrote, so a later setup run can tell
#                   the hand edits apart and carry them over.
# A rewrite that touches "args" must therefore record itself: "args_written"
# is stamped with the new "args" (so setup.py does not read the rewrite as a
# hand edit), and "user_args" is re-stamped with the person's options minus
# the policy flags (a copy of a policy flag in "user_args" would win over
# "args" at engine start). Every option the person set that this module does
# not own survives the rewrite.
#
# One exception: a config an older Strata wrote has no "args_written" at all, and
# setup.py then has its own rule for telling hand edits apart ("an option my new
# args do not have was added by hand"). This script leaves such a file without
# "args_written" rather than inventing it, because inventing it would mark those
# hand edits as generated - and the next `strata --setup` would drop them.
import glob, json, os, sys

# argv[1]: the runtime share path - upstream's own strata_control/user_args.py
# lives there: the same code setup.py and the server use, so the layers cannot
# drift apart (it is stdlib-only).
# argv[2]: "true"/"false" - whether THIS package ships the vision encoder
# (packages/strata/default.nix, visionEncoder): see the "vision" rule above.
share = sys.argv[1]
vision_encoder = sys.argv[2] == "true"
home = os.environ.get("STRATA_HOME") or os.path.expanduser("~/.local/share/strata")

sys.path.insert(0, share)
from strata_control import user_args as UA

# The options this module owns, (re)written into "args" below: a copy of any
# of them in "user_args" is dropped (that layer would otherwise win over the
# value this module just set). Everything the person set that is not listed
# here survives.
POLICY = {
    "--expert-cache",
}

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
        if "--expert-cache" not in a:
            a += ["--expert-cache", "auto"]
        if not vision_encoder:
            c.pop("vision", None)
        c["args"] = a
        # The person's options, before this rewrite: "user_args" plus anything
        # in "args" that differs from "args_written" (a hand edit since the
        # last write). The policy flags are skipped: they are ours to set, and
        # a differing value is a stale one, not a choice to keep.
        had_written = UA.WRITTEN_KEY in c
        mine = UA.capture(c, POLICY)
        mine = UA.flat([g for g in UA.groups(mine) if UA.flag_of(g) not in POLICY])
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
