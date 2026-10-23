# Minimal stand-in for Strata's strata_control.user_args used by the
# strata-fail-closed check: the real module ships with the (large) engine
# source tree. Only the functions config_patch.py calls are implemented, and
# only for a config with no hand-edited user_args layer.
def capture(config, policy):
    return []

def flat(groups):
    return [arg for group in groups for arg in group]

def groups(mine):
    return mine

def flag_of(group):
    return group[0] if group else None

def stamp(config, mine):
    config["args_written"] = list(config.get("args") or [])
