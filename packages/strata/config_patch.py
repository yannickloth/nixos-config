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
#
# Component migration (0.2.16+): configurations written by older packages name
# the engine by path. Up to 0.2.15 this package kept it at
# $STRATA_HOME/engine/strata (a symlink into the store), so a run config holds
# an absolute path there; an older Nix build could also point into /nix/store
# directly. 0.2.17 keeps the engine in the component folder instead, and both
# `strata launch` and the desktop app write `exe: "component:strata-engine"`.
# This script rewrites every such path once; a component reference is left as
# it is, so a rerun changes nothing.
#
# `vision.exe` is NOT rewritten to a component reference: a reference always
# resolves to the engine entrypoint (serve/server.py -> _component_exe ->
# engine_component.expand), which would start the engine as the picture
# reader. It is written as the absolute path of the reader inside the
# component folder, which is where setup.py puts it and where
# serve/server.py's with_current_reader() looks for it.
import glob, json, os, sys

# argv[1]: the runtime share path - upstream's own strata_control/user_args.py
# lives there: the same code setup.py and the server use, so the layers cannot
# drift apart (it is stdlib-only).
# argv[2]: "true"/"false" - whether THIS package ships the vision encoder
# (packages/strata/default.nix, visionEncoder): see the "vision" rule above.
# argv[3]: the component folder name ("0.1.63-linux-x86_64-cuda"); optional, so
# a call without it simply skips the vision.exe rewrite.
share = sys.argv[1]
vision_encoder = sys.argv[2] == "true"
component_folder = sys.argv[3] if len(sys.argv) > 3 else ""
home = os.environ.get("STRATA_HOME") or os.path.expanduser("~/.local/share/strata")

# Where upstream keeps the engine packages: components_dir() in
# strata_control/engine_component.py uses XDG_DATA_HOME, not STRATA_HOME.
components = os.path.join(
    os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share"), "strata", "components")
vision_exe = os.path.join(components, "engine", component_folder, "strata-vision") if component_folder else ""

sys.path.insert(0, share)
from strata_control import user_args as UA

# The options this module owns, (re)written into "args" below: a copy of any
# of them in "user_args" is dropped (that layer would otherwise win over the
# value this module just set). Everything the person set that is not listed
# here survives.
POLICY = {
    "--expert-cache",
}

# --- Component migration (0.2.16+) ---
# Rewrites a path-based `exe` to the component reference. Idempotent: once
# written, a rerun changes nothing (so the mtime order strata-server uses to
# pick the served model survives). Done before the policy rewrite because that
# rewrite already touches the file; doing it first means one write, not two.
component_ref = "component:strata-engine"


def stale_path(value):
    """True for a binary path an older Strata wrote: a store path, the old
    engine/ tree, or a path that is simply not there any more. A current path
    (or a component reference) is not stale."""
    if not isinstance(value, str) or not value:
        return False
    if value.startswith("component:"):
        return False
    if value.startswith("/nix/store/") or value.startswith("./engine/") or value.startswith("engine/"):
        return True
    old_engine = os.path.join(home, "engine")
    if value == old_engine or value.startswith(old_engine + os.sep):
        return True
    return not os.path.exists(value) and not os.path.exists(os.path.join(home, value))


for p in sorted(glob.glob(os.path.join(home, "strata-*.json"))):
    if p.endswith(".shared-settings.json"):
        continue
    try:
        with open(p, encoding="utf-8") as f:
            text = f.read()
        c = json.loads(text)
        if not isinstance(c, dict):
            continue
        migrated = False
        if stale_path(c.get("exe")):
            c["exe"] = component_ref
            migrated = True
        # The picture reader: a concrete path inside the component folder, never
        # a component reference (a reference resolves to the ENGINE, not to
        # strata-vision). A build without the encoder drops the block below.
        vision = c.get("vision")
        if isinstance(vision, dict) and vision_encoder and vision_exe and "exe" in vision:
            if vision["exe"] != vision_exe:
                vision["exe"] = vision_exe
                migrated = True
        if migrated:
            tmp = p + ".tmp"
            with open(tmp, "w", encoding="utf-8") as f:
                f.write(json.dumps(c, indent=1))
            os.replace(tmp, p)
    except Exception:
        pass  # migration failures are non-fatal, skip to policy check

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
