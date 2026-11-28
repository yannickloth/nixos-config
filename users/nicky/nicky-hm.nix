# Standalone home-manager config for nicky.
# Build/apply via the consolidated flake: home-manager switch --flake ~/code/nixos-config/users
# (or per-host via the main flake's home-manager.users.nicky).
#
{ config
, pkgs
, lib
, ...
}:

let
  # Tresorit FHS environment definition
  tresoritFHS = pkgs.buildFHSEnv {
    name = "tresorit-fhs";
    targetPkgs = pkgs: with pkgs; [
      qt5.qtbase
      libsForQt5.qtscript
      libsForQt5.qtx11extras
      libsForQt5.qtdeclarative
      libsForQt5.qtsvg
      libsForQt5.qtgraphicaleffects
      libsForQt5.qtquickcontrols2
      libsForQt5.qtwayland
      fuse
      libxcb
      libx11
      glibc
      libgcc
      pcre2
      libcap
      libxcb-wm
      libxcb-image
      libxcb-keysyms
      libxcb-render-util
      libxkbcommon
      libxext
      xcb-util-cursor
      xcbutilxrm
      libGLU
      libGL
      krb5
    ];
    runScript = "bash";
    meta = with pkgs.lib; {
      description = "FHS environment for Tresorit";
    };
  };
  # True when this config targets laptop-p16, carried via commonHm.hostName.
  # That option is set by the standalone flake (users/flake.nix, used on
  # CachyOS) and by the NixOS host (hosts/laptop-p16/laptop-p16.nix). Note
  # config.networking.hostName is NOT reachable inside home-manager modules
  # (they expose their own config namespace), so it cannot be used here.
  isP16 = config.commonHm.hostName == "laptop-p16";
  # True when this config targets server-nike (Dell 5810). It runs the same
  # software stack as laptop-p16 — its intended use is inference (daily),
  # with desktop use in between — and the hardware qualifies: RTX 3060 12GB
  # (Ampere GA106, sm_86, above the image's sm_75 floor) + 96 GiB RAM for
  # Strata's expert arena.
  isNike = config.commonHm.hostName == "server-nike";
  # True when this config is built by the standalone CachyOS flake
  # (users/flake.nix). On CachyOS the engine's host tuning lives in /etc
  # (hosts/laptop-p16/cachyos/), because no NixOS system module runs there; on
  # the NixOS host it is provided by hosts/laptop-p16/ instead. Gating keeps
  # the CachyOS-only activation out of a future NixOS install.
  isCachyOS = config.commonHm.isCachyOS;
  # Runtime path of nicky's agenix-decrypted personal API keys (see age.secrets).
  nickyApiKeysPath = config.age.secrets."nicky.nix".path;
in
{
  imports = [
    ../common-hm.nix
    ../emacs-adult.nix
    ../../packages/strata/home.nix
    ../../packages/unsloth-studio/home.nix
    ../../packages/litellm-proxy/home.nix
    ../../packages/kintsugi-27b/home.nix
    ../natural-scroll.nix
    ../nix-serve.nix
    ../opencode.nix
    ../graphrag-watch.nix
    ../../packages/orca/home.nix
    ../../packages/browseros/home.nix
    ../../packages/libreoffice-mcp/home.nix
    ../../packages/opencode-desktop/home.nix
    ../../packages/rea/home.nix
    ../../packages/herdr/home.nix
  ];

  # Global opencode provider/model config (deepseek, Z.AI GLM Coding Plan
  # subscription, Kimi, Hetzner).
  opencode.enable = true;
  # Standalone GraphRAG change detector: marks content edited outside opencode
  # (pi, IDE, scripts) dirty so the next build picks it up. See graphrag-watch.nix.
  graphragWatch.enable = true;
  # On CachyOS there is no system agenix / /etc/secrets, so source the provider
  # keys from the home-manager agenix secret decrypted with ~/.ssh/agenix_nicky
  # (see the `age` block below). On NixOS hosts keep the default /etc/secrets.
  opencode.envFile =
    lib.mkIf config.commonHm.isCachyOS config.age.secrets."opencode-keys.env".path;

  # Orca (agent development environment): the desktop client on every host, and
  # on the inference hosts (laptop-p16, server-nike) the always-on runtime
  # server (`orca-ide serve`) that other clients pair to over Tailscale.
  # Per-user: it runs as nicky, so the agent CLIs it drives use nicky's PATH
  # and credentials.
  orca.enable = true;

  # BrowserOS neo: agent-driven browser for AI assistants (MCP), runs with the
  # user's real logins in its own profile.
  browseros.enable = true;

  # hermes-agent: route through the LiteLLM rank gateway on server-nike. The
  # `model.default` uses a rank name (lieutenant) so the proxy handles routing,
  # fallback and cost tracking. The unsloth studio custom provider stays so
  # local inference models are still reachable for experimentation.
  #
  # The gateway and the two subscription backends are registered as hermes
  # custom_providers, so hermes also has a path that does NOT depend on the
  # gateway: when the proxy is down, switch provider to zai-coding or
  # kimi-code and the request goes to the plan endpoint itself (the built-in
  # deepseek provider is a third direct path; hermes auth manages its
  # DEEPSEEK_API_KEY in ~/.hermes/.env). Credentials ride via key_env -> the
  # vars writeHermesEnv upserts into ~/.hermes/.env (hermes' own API-key
  # file, loaded into the process env at startup), sourced from the same
  # opencode-keys agenix secret as every other key file. The proxy entry also
  # fixes gateway auth itself: until now hermes had no stored credential for
  # model.provider=proxy (no custom_providers entry named proxy, no key_env,
  # no auth pool), so its provider resolver came back empty — hermes could
  # not authenticate a gateway request at all (the proxy requires the master
  # key).
  #
  # Written as an activation running after herdrIntegrations: the herdr
  # integration install command rewrites the model/provider/base_url section,
  # so a plain home.file would be clobbered. This activation patches those
  # three fields (and adds the orca-status plugin) after herdr finishes.
  # custom_providers is upserted the same way: entries with our names are
  # replaced, every other entry (hermes' own, e.g. unsloth studio) survives.
  # The gateway URL is per-host (config.opencode.proxyBaseURL): the local
  # proxy on NixOS laptop-p16, the server-nike gateway over Tailscale
  # elsewhere — the same value opencode/pi point at.
  home.activation.writeHermesConfig = lib.hm.dag.entryAfter [ "writeBoundary" "herdrIntegrations" "writeHermesEnv" ] ''
    # Bootstrap: create ~/.hermes/config.yaml if nothing else did (herdr's
    # `integration install hermes` usually does; on a fresh home the patch
    # below would otherwise skip forever and hermes would start with no
    # provider config). Skips a file that already has content, replaces an
    # empty one (yq -i no-ops on empty input). Dry-run safe: $DRY_RUN_CMD
    # prefix, no shell redirection.
    $DRY_RUN_CMD ${pkgs.python3}/bin/python3 - "$HOME" <<'PYEOF'
    import os, sys

    path = os.path.join(sys.argv[1], ".hermes", "config.yaml")
    if os.path.exists(path) and os.path.getsize(path) > 0:
        sys.exit(0)
    os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT, 0o600)
    os.fchmod(fd, 0o600)
    with os.fdopen(fd, "w") as out:
        out.write("model:\n  default: lieutenant\n  provider: proxy\n  base_url: ${config.opencode.proxyBaseURL}\ncustom_providers: []\n")
    print(f"hermes: created base config {path}")
    PYEOF
    # Patch any existing mapping (herdr-created, hermes-created, or the base
    # above). type == "object" also covers a file that exists without a model
    # section yet (herdr's first state), which the old .model.default guard
    # skipped.
    if $DRY_RUN_CMD ${pkgs.yq}/bin/yq -e 'type == "object"' "$HOME/.hermes/config.yaml" >/dev/null 2>&1; then
      $DRY_RUN_CMD ${pkgs.yq}/bin/yq -iy '
        .model = {"default": "lieutenant", "provider": "proxy", "base_url": "${config.opencode.proxyBaseURL}"}
      ' "$HOME/.hermes/config.yaml"
      $DRY_RUN_CMD ${pkgs.yq}/bin/yq -iy '.plugins.enabled += ["orca-status"]' "$HOME/.hermes/config.yaml"
      # Gateway + direct subscription providers (idempotent: same-named
      # entries are replaced, unknown ones kept). key_env names point at the
      # vars written by writeHermesEnv; hermes' named-custom branch supplies
      # them as the bearer credential.
      $DRY_RUN_CMD ${pkgs.yq}/bin/yq -iy '
        .custom_providers = ((.custom_providers // []) | map(select(.name != "proxy" and .name != "zai-coding" and .name != "kimi-code"))) + [
          {"name": "proxy", "base_url": "${config.opencode.proxyBaseURL}", "key_env": "LITELLM_MASTER_KEY", "model": "lieutenant", "models": {"lieutenant": {}}},
          {"name": "zai-coding", "base_url": "https://api.z.ai/api/coding/paas/v4", "key_env": "ZAI_CODING_API_KEY", "model": "glm-5.3", "models": {"glm-5.3": {}, "glm-5.3-flash": {}, "glm-5-turbo": {}}},
          {"name": "kimi-code", "base_url": "https://api.kimi.com/coding/v1", "key_env": "KIMI_CODE_API_KEY", "model": "k3.1-pro", "models": {"k3.1-pro": {}, "k3": {}, "k3-256k": {}, "kimi-for-coding": {}}}
        ]
      ' "$HOME/.hermes/config.yaml"
    else
      echo "hermes: config.yaml missing or not a mapping; skipping model override" >&2
    fi
  '';

  # hermes credential source: upsert the gateway master key and the two
  # subscription backend keys into ~/.hermes/.env (hermes loads that file
  # into the process env at startup; the custom_providers entries above
  # reference the vars through key_env). Same source as every other key file
  # on this machine: the OPENAI_API_KEYS agenix secret (config.opencode.envFile,
  # falling back to the system path), so a rotation reaches hermes on the
  # next switch too. Only the three managed vars are touched; other lines
  # (hermes auth's own entries, e.g. DEEPSEEK_API_KEY) stay verbatim.
  # Freshness: every hermes CLI run loads the file at startup, but the
  # hermes-gateway service is hermes' own unit (not HM-managed), so it sees
  # new or rotated values only after its next restart.
  home.activation.writeHermesEnv = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    # Wrapped in $DRY_RUN_CMD like writeHermesConfig, so a dry activation
    # touches nothing under ~/.hermes. (The key-file materialization in
    # users/opencode.nix deliberately stays unwrapped; this file follows the
    # wrapped convention.)
    $DRY_RUN_CMD ${pkgs.python3}/bin/python3 - "${config.home.homeDirectory}" '${config.opencode.envFile}' <<'PYEOF'
    import json, os, sys

    home = sys.argv[1]
    # expandvars so an agenix $XDG_RUNTIME_DIR/... path resolves from the
    # activation environment (same convention as setupOpenCodeKeys).
    candidates = [os.path.expandvars(p) for p in (sys.argv[2], "/etc/secrets/opencode-keys.env") if p]
    envfile = next((p for p in candidates if p and os.path.exists(p)), None)
    env_path = os.path.join(home, ".hermes", ".env")
    # secret URL -> env var name (both Z.AI spellings hold the same plan key;
    # see the mapping in users/opencode.nix).
    mapping = {
        "http://server-nike.bee-blues.ts.net:4000/v1": "LITELLM_MASTER_KEY",
        "https://api.z.ai/api/paas/v4/": "ZAI_CODING_API_KEY",
        "https://api.z.ai/api/coding/paas/v4": "ZAI_CODING_API_KEY",
        "https://api.kimi.com/coding/v1": "KIMI_CODE_API_KEY",
    }
    managed = set(mapping.values())
    if envfile is None:
        print("hermes: no key source found (%s); skipping .env update" % ", ".join(candidates))
        sys.exit(0)
    try:
        with open(envfile) as fh:
            _, _, payload = fh.read().partition("=")
        keys = json.loads(payload.strip())
    except Exception as exc:
        print(f"hermes: failed to parse {envfile}: {exc}; leaving .env untouched", file=sys.stderr)
        sys.exit(0)
    values = {}
    for url, var in mapping.items():
        key = keys.get(url)
        if key:
            values[var] = key
    missing = sorted(managed - set(values))
    if missing:
        print(f"hermes: no secret key for {', '.join(missing)}; those vars not written")
    # Keep unmanaged lines in order (blank lines are dropped); managed ones
    # move to the end, upserted.
    kept = []
    try:
        with open(env_path, encoding="utf-8") as fh:
            kept = [l.rstrip("\n") for l in fh if l.strip() and l.split("=", 1)[0] not in managed]
    except FileNotFoundError:
        os.makedirs(os.path.dirname(env_path), mode=0o700, exist_ok=True)
    for var in sorted(values):
        kept.append(f"{var}={values[var]}")
    fd = os.open(env_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    os.fchmod(fd, 0o600)
    with os.fdopen(fd, "w") as out:
        if kept:
            out.write("\n".join(kept) + "\n")
    print(f"hermes: wrote {len(values)} key var(s) to {env_path}")
    PYEOF
  '';

  # LibreOffice MCP extension (packages/libreoffice-mcp): an MCP server runs
  # inside the open LibreOffice window on https://localhost:8765/mcp (the
  # default port; aeiuno uses 8766 so parallel sessions cannot attach to each
  # other's documents), so agents edit the document the user is looking at.
  # Registered in users/opencode.nix.
  libreofficeMcp.enable = true;
  # Same build as the app in home.packages (libreoffice-qt6, not pkgs.libreoffice
  # default): `unopkg` must come from the LibreOffice that actually runs, so the
  # extension registers into the profile that build reads.
  libreofficeMcp.libreoffice = pkgs.libreoffice-qt6;

  # opencode Desktop: the GUI of the opencode v2 line, next to the `opencode`
  # CLI in home.packages below. Both read ~/.config/opencode; the desktop app
  # runs its own bundled agent server.
  opencode-desktop.enable = true;

  # REA: reverse-engineering MCP server + CLI (packages/rea/home.nix) and the
  # "reverse-engineer-anything" agent skill.
  rea.enable = true;

  # herdr (packages/herdr/home.nix): terminal multiplexer / runtime for coding
  # agents, plus its agent skill and the integrations for the agents installed
  # here (opencode, pi, hermes) — those `herdr integration install` runs happen
  # at activation, see the module.
  herdr.enable = true;
  orca.server = lib.mkIf (isP16 || isNike) {
    enable = true;
    # No Tailscale address pinned: the launcher derives it at start.
  };

  # Laya is gone entirely: package, flake output, home/nixos modules, the
  # laya-mcp user service and the (gated) opencode MCP entry all removed. It was
  # disabled since 2026-09-28, and Unsloth Studio's Decision API already serves
  # the same System One shape locally — POST /v1/systemone and the
  # /mcp/decisions MCP mount, the latter registering as opencode's `systemone`
  # server — so a second engine with its own checkpoint, venv and port had
  # nothing left to add. Recoverable from git if it is ever wanted back.

  # CLM is gone entirely: package, flake output, module and service units all
  # removed. Unsloth Studio's Decision API serves the same System 1 shape
  # locally — POST /v1/systemone plus the /mcp/decisions MCP mount — and runs
  # the model on CPU, so a separate stack (Qwen3-8B pooling encoder wanting
  # ~17 GB of VRAM on top of Strata and Studio, plus a 75 MB head on
  # clm-serve) had nothing left to add here. It was never provisioned either:
  # no ~/.local/share/clm venv ever existed, so both units sat installed and
  # inactive. Recoverable from git if the engine is ever wanted back.

  # Unsloth Studio on every host (packages/unsloth-studio/home.nix): the
  # local inference UI/API and — the reason it left its laptop-p16-only gate
  # — the Decision API, which serves open System One models (Laya, ...) on a
  # TypeSafe-compatible /v1/systemone. This is the local decisional endpoint:
  # the opencode `systemone` MCP reaches it through the native /mcp/decisions
  # mount, and the systemone plugin (llm-harness-plugins/systemone) posts its
  # packaged judgments to /v1/systemone. Its model and device live in Studio's DB
  # panel, not here; that module's header records why the env overrides are
  # deliberately unset.
  # ONE instance per host: Studio installs per-user into $HOME and binds
  # :8888, so aeiuno does not enable it — her opencode reaches the same
  # localhost endpoint. Hosts set users.users.nicky.linger = true so the API
  # survives logout.
  unsloth-studio.enable = true;
  # Container backend on every host (packages/unsloth-studio/container.nix):
  # Studio is built for a normal Linux userland — its installer, in-place
  # llama.cpp rebuilds, audio/image engine swaps and self-update all assume
  # one — so the upstream image under rootless podman is the supported path,
  # and the native install.sh backend (backend = "native") stays available as
  # the fallback for a host that cannot run it. /data holds the graphroot and
  # the model data (family-laptop.nix tmpfiles): a separate LUKS+btrfs volume
  # on laptop-p16 and laptop-hera, a root-disk directory on laptop-xps, which
  # has no second drive.
  unsloth-studio.backend = "container";
  unsloth-studio.podmanStorageRoot = "/data/containers/nicky";
  unsloth-studio.dataDir = "/data/unsloth";
  # GPU passthrough only where the card is at or above the image's sm_75
  # (Turing) floor: laptop-p16's A3000 (sm_86) and server-nike's RTX 3060
  # (sm_86), with the CDI spec from hardware.nvidia-container-toolkit.
  # laptop-hera's GTX 1050 Ti is Pascal (sm_61) — the image's entrypoint
  # exits 1 when it sees such a card — and laptop-xps has no NVIDIA card at
  # all; both run the image in CPU mode.
  unsloth-studio.gpu = isP16 || isNike;
  # Inference hosts only: publish the port beyond loopback so the other
  # inference host / the LAN / the tailnet can reach the UI and API (the host
  # firewall scopes the exposure, see hosts/<host>/<host>.nix). The other hosts
  # keep the loopback-only publish.
  unsloth-studio.host = lib.mkIf (isP16 || isNike) "0.0.0.0";

  # Unsloth Studio needs $STRATA_API_KEY for the handoff script (see
  # handoff.nix).  The unsloth-studio module doesn't import the strata module
  # so it can't reference config.strata.apiKey directly: we write a shared
  # env-file via home.activation and read it from systemd here.
  # The leading dash makes it optional: if the file is missing (first boot
  # before activation), systemd skips it instead of failing the unit.
  systemd.user.services.unsloth-studio.Service.EnvironmentFile = [
    "-${config.home.homeDirectory}/.config/strata/api-key.env"
  ];

  # Only the CachyOS install has the distro podman: there it shares conmon,
  # netavark and the CDI spec with the `podman` in the shell. On NixOS the
  # module's default (pkgs.podman) is used.
  unsloth-studio.podman = lib.mkIf (isCachyOS && isP16) "/usr/bin/podman";
  # On the Strata host, free the card before Studio allocates (packages/
  # unsloth-studio/handoff.nix). The helper is a host script, so it serves both
  # backends; the in-load half of the handoff (LLAMA_SERVER_PATH) is native-only,
  # because inside the container llama.cpp is baked into the image.
  unsloth-studio.strataGpuHandoff = isP16 || isNike;

  # Strata (Qwen3.8-Flash-Next 125B MoE inference, OpenAI/Anthropic API on
  # localhost). Both inference hosts qualify on the card: laptop-p16's RTX A3000
  # 12GB and server-nike's RTX 3060 12GB are sm_86, and both have the RAM for the
  # expert arena (128 GiB and 94 GiB). server-nike ran the same model line before
  # 2026-11-19 — its own settings.json calibration records 39.4 tok/s on
  # swift-1.5-iq3_xxs at 131072 context. Each host serves its own :8080; the
  # LiteLLM proxy (services/litellm-proxy.nix) is the single place that decides
  # which host the shared ranks point at. `dataOnDataVolume` keeps the model files
  # on /data (laptop-p16 only, see below).
  #
  # Upstream 0.2.23: engine/Control 0.1.70. The Hy4-Flash shape engine is a
  # separate component fetched on demand; the Qwen 125B keeps the engine this
  # package builds. Still the 0.2.17 defaults: route-tail-skip OFF, 17 GB RAM free.
  # The engine is an upstream engine component (versioned, per-file manifest)
  # built in the Nix store — the app and the Terminal are version-locked together.
  # All engine tuning (context, KV format, rope scaling, PCIe fraction, pool
  # workers, adapt-every, spec-min-p) is left to `strata --setup` at runtime.
  # Nix manages only service lifecycle: start/stop, GPU handoff, deployment layout.
  strata = lib.mkIf (isP16 || isNike) {
    enable = true;
    # Reachable beyond loopback (the other inference host, the LAN, the
    # tailnet); the host firewall scopes it to private ranges (see
    # hosts/<host>/<host>.nix). The server's Host-header check still guards
    # non-localhost names - see allowedHosts below.
    host = "0.0.0.0";
    # Keep the engine resident far longer than the 5-minute default: a reload
    # puts the weights back before decode can start, and an idle window shorter
    # than the reload costs that stall on every gap longer than the window.
    # - server-nike: reload ~116 s (39.97 GiB of experts at 0.51 GiB/s,
    #   measured 2026-11-22), so 900 s pays off up to 15-minute gaps.
    # - laptop-p16: the same reload takes ~869 s (2026-11-22): the 70 GiB of
    #   model files read from the /data NVMe at ~50-120 MB/s, and the 24 GiB of
    #   mlocked model pages must be resident in a machine that has ~4 GiB free.
    #   At 900 s almost every gap over 15 minutes costs a 14-minute load that
    #   no client timeout can wait for, so hold the ~55 GB for the hour: 3600 s.
    idleUnloadSeconds = if isP16 then 3600 else 900;
    # The picture reader is built and shipped (visionEncoder), so `strata launch`
    # asks the images question and either answer works instead of failing on a
    # package without the binary. Answer it in the run config, not here: on this
    # 12 GB card images cost ~35 -> ~22 tok/s. Shipping the encoder costs disk
    # only until a model uses it.
    visionEncoder = true;
    # The desktop app (upstream AppImage): shares the models below and can
    # either load one with its own engine or use the API of a running server -
    # e.g. add http://127.0.0.1:8080/v1 as a custom connection. Nothing is
    # stopped on launch (stopServerOnLaunch) for that reason.
    desktop.enable = true;
    # The other half of the Studio handoff (packages/unsloth-studio/home.nix
    # frees the card FROM Strata FOR Studio; these free it FROM Studio FOR
    # Strata). Naming a Strata model while Studio holds the card must not end
    # in a failed cudaMalloc: beforeLoad asks Studio to unload its own model
    # first, and minFreeVramMib is the backstop that refuses the load (503 +
    # Retry-After) if VRAM is still short after the hook. idleUnloadSeconds
    # above is 3600 on laptop-p16 and 900 on server-nike, so Strata holds the
     # card deliberately long - a Studio turn
    # inside that window is exactly the case this covers.
    minFreeVramMib = 8000;
    # The Studio container reaches Strata through pasta's host loopback
    # (packages/unsloth-studio/container.nix, option hostLoopback), so requests
    # arrive with this Host header. Strata 403s anything but localhost otherwise
    # (DNS-rebinding protection). The tailnet's MagicDNS domain covers access by
    # name over Tailscale (<node>.bee-blues.ts.net); IP addresses and the host's
    # own name pass the check without an entry.
    allowedHosts = [ "host.containers.internal" "169.254.1.2" ".bee-blues.ts.net" ];
    beforeLoad = "${config.home.homeDirectory}/.local/bin/unsloth-studio-unload.sh";
    apiKey = "strata";
    # Force the service to serve this declarative config so the UI cannot
    # overwrite the API key (the UI writes into the run config, which then
    # overrides the env var).
    defaultConfig = "$HOME/.config/strata/run.json";
    # The declarative run config is installed by the file below. It must
    # match what `strata launch` writes, except `api_key` is always "strata"
    # so the UI cannot generate a random key and break the proxy.
    # Store everything Strata reads and writes on the /data volume: the
    # runtime tree (~/.local/share/strata -> /data/strata) and the model files
    # (~/.local/share/Strata-data -> /data/Strata-data). The activation moves
    # each tree and symlinks it back, so the data_dir in ~/.config/strata/
    # settings.json and the absolute --native/--pack/--mtp paths in every
    # strata-*.json keep resolving unchanged, and a fresh setup downloads to
    # /data. The first run stops strata.service for the copy: 116 GiB takes
    # ~10 min at 200 MB/s (~5 min at 400 MB/s, ~21 min at 100 MB/s), so run
    # the rebuild from a terminal, not from a chat session that is using the
    # model.
    # laptop-p16 only: server-nike keeps both trees on its home partition (its
    # ~167 GB of models already live there, and /home has 1.5 TB free). Set this
    # to true on nike to move them to /data/strata and /data/Strata-data.
    dataOnDataVolume = isP16;
  };

  # Kintsugi-27B (Qwen3.8-27B at 2.47 bits, EXL3 trellis format): disabled
  # everywhere on both inference hosts. Strata (125B MoE at ~30+ tok/s) is
  # faster and stronger; Unsloth Studio provides its own 125B and 32B models.
  # The EXL3 trellis quantization requires the Kintsugi bundle's engine binary,
  # which is not served by Unsloth Studio or Strata. Kintsugi is disabled
  # because the only model it serves (27B) is outclassed by Strata's 125B MoE.
  # Recoverable from git if a stronger EXL3 model ever appears.
  # Enable the shared developer tools (neovim, vscode, direnv, etc.)
  # LiteLLM proxy: rank gateway on laptop-p16 only, CachyOS variant.
  # NixOS hosts (server-nike, future laptop-p16) use the system module.
  litellm-proxy.enable = isP16 && isCachyOS;

  commonHm.enableDeveloperTools = true;

  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "nicky";
  home.homeDirectory = "/home/nicky";

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = with pkgs; [
    # # Adds the 'hello' command to your environment. It prints a friendly
    # # "Hello, world!" when run.
    # pkgs.hello

    charis # SIL Charis, a serif font recommended for readability
    stix-two # STIX Two, a Unicode font covering scientific and mathematical notation

    # # It is sometimes useful to fine-tune packages, for example, by applying
    # # overrides. You can do that directly here, just don't forget the
    # # parentheses. Maybe you want to install Nerd Fonts with a limited number of
    # # fonts?
    # (pkgs.nerdfonts.override { fonts = [ "FantasqueSansMono" ]; })

    # # You can also create simple shell scripts directly inside your
    # # configuration. For example, this adds a command 'my-hello' to your
    # # environment:
    # (pkgs.writeShellScriptBin "my-hello" ''
    #   echo "Hello, ${config.home.username}!"
    # '')

    bun
    bat
    digikam # photo management / organizer
    fd
    jq
    lsd
    netcat
    nil # Nix Language Server
    ripgrep
    tree # Command to produce a depth indented directory listing
    typst # New markup-based typesetting system that is powerful and easy to learn
    jetbrains-toolbox # JetBrains IDEs (IntelliJ, PyCharm, ...) via Toolbox
    typstyle # Format your typst source code
    yq
    yed

    git-lfs
    gh

    (pkgs.callPackage ../../packages/masterpdfeditor { })
    obsidian

    languagetool
    opencode
    pi-coding-agent
    hermes-agent
    magpie
    deepseek-harness

    jdk25 # Java 25
    elan # Lean theorem prover version manager

    rclone # Used to mount nestor shares
    fuse3 # provides fusermount3, used by the nestor-mount unit below

    quarto
    # panache

    jbang

    # Merged from the previous nicky-hm.nix config
    amarok
    anki-bin
    (aspellWithDicts (dicts: with dicts; [ en en-computers en-science de fr nl wa ])) # for emacs
    audacious
    audacious-plugins
    audacity
    bottles
    calibre
    cobang # QR code scanner desktop app for Linux
    conda # Conda is a package manager for Python
    curlFull
    devbox
    fdk_aac # A high-quality implementation of the AAC codec from Android
    fdk-aac-encoder # Command line encoder frontend for libfdk-aac encoder
    flatpak
    freac
    fsearch
    gimp
    gnome-disk-utility
    gnome-software
    gparted
    hunspellDicts.fr-any
    hunspellDicts.en_US-large
    hunspellDicts.en_GB-large
    hunspellDicts.de_DE
    inkscape-with-extensions
    jetbrains-toolbox
    kdePackages.dolphin
    kdePackages.elisa
    kdePackages.filelight
    kdePackages.gwenview
    kdePackages.kalk
    kdePackages.kate
    kdePackages.okular
    # KDE mini-games: adults get them natively, kids via gated flatpak
    # (apps.flatpak.apps) — never both for the same user (see games/games.nix).
    kdePackages.granatier
    kdePackages.katomic
    kdePackages.kblocks
    kdePackages.kbreakout
    kdePackages.kdiamond
    kdePackages.kmahjongg
    kdePackages.kmines
    kdePackages.kpat
    kdePackages.kshisen
    kdePackages.ksudoku
    keepassxc
    kid3-qt # A simple and powerful audio tag editor
    kodi
    krita
    gnuplot # Command-line plotter for computed numbers (functions, data)
    # Qt6/KDE build of the same 25.8.5.2: the plain `libreoffice` ships only the
    # gen+gtk3 VCL plugins, so on this Wayland/KDE session it reads the user's
    # dark GTK theme (adw-gtk3-dark) even though Plasma is BreezeLight, and its
    # "Application Colors = Automatic" then resolves to dark. The qt6 build has
    # --enable-qt6, follows the Plasma colour scheme, and keeps native Wayland +
    # KDE dialogs. libreofficeMcp.libreoffice must match it (see below).
    libreoffice-qt6
    lua
    lutris
    mastodon
    maxima # Computer algebra system: integrate, solve, limit, sum, ODEs (CLI `maxima`)
    meld # Visual diff and merge tool
    mousai # Identify any songs in seconds
    musescore
    pantheon.sideload
    pdfstudioviewer # Easy to use, full-featured PDF viewing software.
    plantuml
    podman-desktop
    powershell # Powerful cross-platform (Windows, Linux, and macOS) shell and scripting language based on .NET
    qalculate-qt
    recoll
    scrcpy
    scribus
    signal-desktop
    speechd # speech-dispatcher, useful for Firefox
    szyszka # A simple but powerful and fast bulk file renamer
    thunderbird
    tinymist # Integrated language service for Typst
    tuner
    vlc # native media player (parents only; kids use the gated flatpak)
    libmicrodns # for playing from VLC onto ChromeCast
    protobuf # for playing from VLC onto ChromeCast
    whitesur-gtk-theme
    catfish
    zeal # Simple offline API documentation browser.
    zoom-us
    zotero

    tresoritFHS
  ];
  home.file.".npmrc".text = ''
    prefix=${config.home.homeDirectory}/.npm-global
  '';

  # Add local bin, npm global bin, and elan to PATH
  home.sessionPath = [
    "$HOME/.local/bin"
    "$HOME/.elan/bin"
    "$HOME/.npm-global/bin"
  ];

  home.activation.setupTresorit = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        # Install Tresorit if not already installed. The installer is fetched
        # by Nix at build time (pinned hash) instead of downloaded from a
        # mutable URL at activation: reproducible, MITM-proof, and it does not
        # silently change between switches. It is copied to a private temp file
        # (never a predictable /tmp path a local user could pre-create), and a
        # failure only warns instead of aborting the whole switch.
        TRESORIT_INSTALLER=${pkgs.fetchurl {
          url = "https://installer.tresorit.com/tresorit_installer.run";
          sha256 = "106h54na02x27qx0m8qspk9iivp00x25dywki6gibxx7y9qrv8vi";
        }}
        if [ ! -f "$HOME/.local/share/tresorit/tresorit" ]; then
          echo "Installing Tresorit..."
          installer=$(${pkgs.coreutils}/bin/mktemp)
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/cp "$TRESORIT_INSTALLER" "$installer"
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/chmod +x "$installer"
          if ! $DRY_RUN_CMD "$installer" --target "$HOME/.local/share/tresorit" --noexec; then
            echo "setupTresorit: installer failed; leaving Tresorit uninstalled" >&2
          fi
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/rm -f "$installer"
        fi

        # Create desktop file in applications directory
        DESKTOP_FILE="$HOME/.local/share/applications/tresorit-fhs.desktop"
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "$(dirname "$DESKTOP_FILE")"
        if [ -f "$DESKTOP_FILE" ]; then
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/rm -f "$DESKTOP_FILE"
        fi
        $DRY_RUN_CMD cat > "$DESKTOP_FILE" <<EOF
    [Desktop Entry]
    Version=1.0
    Type=Application
    Name=Tresorit FHS
    Comment=Secure cloud storage
    Exec=${config.home.homeDirectory}/.local/share/tresorit/tresorit_fhs_launcher.sh
    Icon=tresorit
    Terminal=false
    Categories=Network;
    EOF

        # Disable Tresorit's broken autostart config
        if [ -f "$HOME/.config/autostart/tresorit.desktop" ]; then
          $DRY_RUN_CMD mv "$HOME/.config/autostart/tresorit.desktop" "$HOME/.config/autostart/tresorit.desktop.bk"
          $DRY_RUN_CMD sed -i 's/^/# /' "$HOME/.config/autostart/tresorit.desktop.bk"
        fi

        # Set up autostart for FHS version
        AUTOSTART_FILE="$HOME/.config/autostart/tresorit-fhs.desktop"
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "$(dirname "$AUTOSTART_FILE")"
        if [ -f "$AUTOSTART_FILE" ]; then
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/rm -f "$AUTOSTART_FILE"
        fi
        $DRY_RUN_CMD cat > "$AUTOSTART_FILE" <<EOF
    [Desktop Entry]
    Version=1.0
    Type=Application
    Name=Tresorit FHS
    Comment=Secure cloud storage
    Exec=${config.home.homeDirectory}/.local/share/tresorit/tresorit_fhs_launcher.sh
    Icon=tresorit
    Terminal=false
    Categories=Network;
    EOF
  '';

  # CachyOS: the Strata engine needs a 2 MiB hugetlb pool covering its whole
  # ~40 GiB arena, and an unlimited RLIMIT_MEMLOCK for the systemd user manager
  # (the strata unit's LimitMEMLOCK=infinity is capped at the manager's 8 MiB
  # otherwise). Both live in /etc, which home-manager cannot write. Apply the
  # bundled installer, but only non-interactively (`sudo -n`) so `home-manager
  # switch` never blocks: run `sudo -v` beforehand to have it applied, else it
  # prints the one command. The future NixOS install uses hosts/laptop-p16/
  # instead and never runs this (isCachyOS is false there).
  home.activation.strataHostTuning = lib.mkIf (isP16 && isCachyOS)
    (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      # Activation scripts run in a restricted environment; make sure sudo is
      # available (it lives on the system PATH, not in the Nix store).
      export PATH="/usr/bin:/usr/sbin:$PATH"
      setup=${../../hosts/laptop-p16/cachyos}
      if [ "$(cat /proc/sys/vm/nr_hugepages 2>/dev/null || echo 0)" -lt 20480 ] \
         || [ ! -e /etc/systemd/system/user@.service.d/99-strata-memlock.conf ]; then
        if sudo -n true 2>/dev/null; then
          $DRY_RUN_CMD sudo "$setup/install.sh"
        else
          echo "strata: host tuning not installed; run once: sudo $setup/install.sh" >&2
        fi
      fi
    '');

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    # Tresorit FHS launcher script
    ".local/share/tresorit/tresorit_fhs_launcher.sh" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        ${tresoritFHS}/bin/tresorit-fhs -c "${config.home.homeDirectory}/.local/share/tresorit/tresorit --hidden" > ${config.home.homeDirectory}/.local/share/tresorit/fhs.log 2>&1 &
      '';
    };
  };

  # Home Manager can also manage your environment variables through
  # 'home.sessionVariables'. These will be explicitly sourced when using a
  # shell provided by Home Manager. If you don't want to manage your shell
  # through Home Manager then you have to manually source 'hm-session-vars.sh'
  # located at either
  #
  #  ~/.nix-profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  ~/.local/state/nix/profiles/profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  /etc/profiles/per-user/nicky/etc/profile.d/hm-session-vars.sh
  #
  home.sessionVariables = {
    MOZ_ENABLE_WAYLAND = "1"; # for Firefox in Wayland sessions
    # Personal API keys (ZAI_CODING_PLAN_API_KEY, DEEPSEEK_API_KEY) are sourced
    # at shell init from the agenix-decrypted file (see programs.zsh.initContent).
    # Pretty man pages via bat: strips the raw formatting and syntax-highlights
    # the man source. `-l man` tells bat the language, `-p` plain (no header).
    MANPAGER = "sh -c 'col -bx | bat -l man -p'";
    # Strata API key: exported so `strata launch` uses it instead of generating
    # a random one (accessed via $STRATA_API_KEY) and so the user can echo it.
    STRATA_API_KEY = "${config.strata.apiKey}";
  };
  home.shellAliases = { };

  # Shared env-file for Unsloth Studio services: they can't reference
  # config.strata.apiKey directly (the unsloth-studio module doesn't import
  # the strata module), so we write a file here and the services read it via
  # EnvironmentFile=.  The handoff scripts use $STRATA_API_KEY.
  home.activation.strataApiKeyFile = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "$HOME/.config/strata"
    printf 'STRATA_API_KEY=%s\n' '${config.strata.apiKey}' > "$HOME/.config/strata/api-key.env"
    chmod 0600 "$HOME/.config/strata/api-key.env"
  '';

  # Declarative Strata run config. The UI saves a random API key on every
  # change, breaking the proxy. This config forces api_key back to "strata"
  # on every activation so the service always serves a valid key.
  # Paths are host-conditional: p16 uses /data/, server-nike uses ~/.local/share/.
  home.file.".config/strata/run.json" = {
    text = builtins.toJSON {
      exe = "component:strata-engine";
      args = [
        "--pack"
        (if isP16 then "/data/Strata-data/packs/swift-iq3_xxs"
          else "${config.home.homeDirectory}/.local/share/Strata-data/packs/swift-iq3_xxs")
        "--native"
        (if isP16 then "/data/Strata-data/models/swift-IQ3_XXS/Swift-Qwen3.8-Flash-Next-GSQ-RCO-IQ3_XXS-00001-of-00002.gguf"
          else "${config.home.homeDirectory}/.local/share/Strata-data/models/swift-IQ3_XXS/Swift-Qwen3.8-Flash-Next-GSQ-RCO-IQ3_XXS-00001-of-00002.gguf")
        "--ple-gguf"
        (if isP16 then "/data/Strata-data/models/swift-IQ3_XXS/Swift-Qwen3.8-Flash-Next-GSQ-RCO-IQ3_XXS-00001-of-00002.gguf"
          else "${config.home.homeDirectory}/.local/share/Strata-data/models/swift-IQ3_XXS/Swift-Qwen3.8-Flash-Next-GSQ-RCO-IQ3_XXS-00001-of-00002.gguf")
        "--expert-profile"
        (if isP16 then "/data/strata/data/expert-profile.bin"
          else "${config.home.homeDirectory}/.local/share/strata/data/expert-profile.bin")
        "--expert-cache" "auto"
        "--prefill" "auto"
        "--spec" "4"
        "--spec-min-p" "0.5"
        "--mtp"
        (if isP16 then "/data/Strata-data/mtp/rt"
          else "${config.home.homeDirectory}/.local/share/Strata-data/mtp/rt")
        "--max-context" "262144"
        "--kv" "int8"
        "--kv-resident" "32768"
        "--vision"
      ];
      cwd = if isP16 then "/data/strata"
        else "${config.home.homeDirectory}/.local/share/strata";
      tokenizer = if isP16 then "/data/Strata-data/packs/swift-iq3_xxs/tokenizer"
        else "${config.home.homeDirectory}/.local/share/Strata-data/packs/swift-iq3_xxs/tokenizer";
      model_name = "swift-1.5-iq3_xxs";
      log = "${config.home.homeDirectory}/.local/state/strata/launch/iq3_xxs-256k.engine.log";
      lib_dirs = [];
      port = 8080;
      gpu = 0;
      gpus_asked = true;
      vision = {
        exe = "${config.home.homeDirectory}/.local/share/strata/components/engine/0.1.70-linux-x86_64-cuda/strata-vision";
        mmproj = if isP16 then "/data/Strata-data/models/mmproj-Swift-Qwen3.8-Flash-Next-BF16.gguf"
          else "${config.home.homeDirectory}/.local/share/Strata-data/models/mmproj-Swift-Qwen3.8-Flash-Next-BF16.gguf";
        model = if isP16 then "/data/Strata-data/models/swift-IQ3_XXS/Swift-Qwen3.8-Flash-Next-GSQ-RCO-IQ3_XXS-00001-of-00002.gguf"
          else "${config.home.homeDirectory}/.local/share/Strata-data/models/swift-IQ3_XXS/Swift-Qwen3.8-Flash-Next-GSQ-RCO-IQ3_XXS-00001-of-00002.gguf";
        gpu = false;
        max_tokens = 300;
        threads = 12;  # p16: 12 threads, server-nike: 6 threads
      };
      api_monitor = true;
      idle_unload_s = 0;
      env = { STRATA_ADAPT_OVERLAP = "0"; };
      args_written = [
        "--pack"
        (if isP16 then "/data/Strata-data/packs/swift-iq3_xxs"
          else "${config.home.homeDirectory}/.local/share/Strata-data/packs/swift-iq3_xxs")
        "--native"
        (if isP16 then "/data/Strata-data/models/swift-IQ3_XXS/Swift-Qwen3.8-Flash-Next-GSQ-RCO-IQ3_XXS-00001-of-00002.gguf"
          else "${config.home.homeDirectory}/.local/share/Strata-data/models/swift-IQ3_XXS/Swift-Qwen3.8-Flash-Next-GSQ-RCO-IQ3_XXS-00001-of-00002.gguf")
        "--ple-gguf"
        (if isP16 then "/data/Strata-data/models/swift-IQ3_XXS/Swift-Qwen3.8-Flash-Next-GSQ-RCO-IQ3_XXS-00001-of-00002.gguf"
          else "${config.home.homeDirectory}/.local/share/Strata-data/models/swift-IQ3_XXS/Swift-Qwen3.8-Flash-Next-GSQ-RCO-IQ3_XXS-00001-of-00002.gguf")
        "--expert-profile"
        (if isP16 then "/data/strata/data/expert-profile.bin"
          else "${config.home.homeDirectory}/.local/share/strata/data/expert-profile.bin")
        "--expert-cache" "auto"
        "--prefill" "auto"
        "--spec" "4"
        "--spec-min-p" "0.5"
        "--mtp"
        (if isP16 then "/data/Strata-data/mtp/rt"
          else "${config.home.homeDirectory}/.local/share/Strata-data/mtp/rt")
        "--max-context" "262144"
        "--kv" "int8"
        "--kv-resident" "32768"
        "--vision"
      ];
      api_key = config.strata.apiKey;  # always "strata"
      open_browser = false;
      args_derived = [
        "--pack"
        (if isP16 then "/data/Strata-data/packs/swift-iq3_xxs"
          else "${config.home.homeDirectory}/.local/share/Strata-data/packs/swift-iq3_xxs")
        "--native"
        (if isP16 then "/data/Strata-data/models/swift-IQ3_XXS/Swift-Qwen3.8-Flash-Next-GSQ-RCO-IQ3_XXS-00001-of-00002.gguf"
          else "${config.home.homeDirectory}/.local/share/Strata-data/models/swift-IQ3_XXS/Swift-Qwen3.8-Flash-Next-GSQ-RCO-IQ3_XXS-00001-of-00002.gguf")
        "--ple-gguf"
        (if isP16 then "/data/Strata-data/models/swift-IQ3_XXS/Swift-Qwen3.8-Flash-Next-GSQ-RCO-IQ3_XXS-00001-of-00002.gguf"
          else "${config.home.homeDirectory}/.local/share/Strata-data/models/swift-IQ3_XXS/Swift-Qwen3.8-Flash-Next-GSQ-RCO-IQ3_XXS-00001-of-00002.gguf")
        "--expert-profile"
        (if isP16 then "/data/strata/data/expert-profile.bin"
          else "${config.home.homeDirectory}/.local/share/strata/data/expert-profile.bin")
        "--expert-cache" "auto"
        "--prefill" "auto"
        "--spec" "4"
        "--spec-min-p" "0.5"
        "--mtp"
        (if isP16 then "/data/Strata-data/mtp/rt"
          else "${config.home.homeDirectory}/.local/share/Strata-data/mtp/rt")
        "--max-context" "262144"
        "--kv" "int8"
        "--kv-resident" "32768"
        "--vision"
      ];
    };
  };

  # agenix (home-manager module): decrypt nicky's personal API keys at activation
  # to $XDG_RUNTIME_DIR/agenix/nicky.nix, then sourced by the shell. The key is
  # ~/.ssh/agenix_nicky, whose public key is the `user-nicky` agenix recipient
  # (see secrets.nix and ssh-keys/users/nicky). ~/.ssh/id_ed25519 is nicky's
  # GitHub SSH identity and is NOT an agenix recipient, so it must not be used
  # here. A missing key fails the build loudly. See secrets-structure/README.md.
  age = {
    identityPaths = [ "/home/nicky/.ssh/agenix_nicky" ];
    secrets."nicky.nix" = {
      file = ../../secrets/nicky.nix.age;
      mode = "0400";
    };
    # Shared LLM provider keys for opencode (OPENAI_API_KEYS JSON), also mounted
    # here so opencode can materialize its per-provider key files on standalone
    # home-manager hosts with no system agenix (CachyOS). See opencode.envFile.
    secrets."opencode-keys.env" = {
      file = ../../secrets/opencode-keys.env.age;
      mode = "0400";
    };
    # PostgreSQL nicky role password — mounted at $XDG_RUNTIME_DIR/agenix/pg-
    # nicky-password so home-manager can wire ~/.pgpass.  The .age file is the
    # same one used by the NixOS service (encrypted to both host keys and the
    # user key).
    secrets."pg-nicky-password" = {
      file = ../../secrets/pg-nicky-password.age;
      mode = "0400";
    };
  };

  # Wire ~/.pgpass so Datagrip and other IDE clients authenticate over TCP
  # without prompting for a password. The raw secret is mounted at
  # $XDG_RUNTIME_DIR/agenix/pg-nicky-password by the home-manager age block
  # above. Written inside the home.activation directory so $DRY_RUN_CMD is
  # honoured during dry-run.
  #
  # Both spellings of the loopback host are listed: libpq (and pgpass) match
  # the connection string *textually*, not the resolved address, so a client
  # told to connect to "127.0.0.1" will not match a "localhost" entry. IDEs
  # and psql get one or the other depending on how they were configured.
  # Unix-socket connections use peer auth and need no entry at all.
  home.activation.pgpass = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    pw_file="$XDG_RUNTIME_DIR/agenix/pg-nicky-password"
    out="$HOME/.pgpass"
    if [ -f "$pw_file" ]; then
      # $(cat) strips the secret's trailing newline(s) and printf adds exactly
      # one back, so each entry is a single line whether or not the .age
      # payload ends with a newline.
      pw=$($DRY_RUN_CMD ${pkgs.coreutils}/bin/cat "$pw_file")
      {
        $DRY_RUN_CMD printf 'localhost:5432:*:nicky:%s\n' "$pw"
        $DRY_RUN_CMD printf '127.0.0.1:5432:*:nicky:%s\n' "$pw"
      } > "$out"
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/chmod 0600 "$out"
    fi
  '';

  programs = {
    zsh = {
      initContent = ''
        # Unset guard to ensure PATH additions are applied even if
        # hm-session-vars.sh was already sourced (e.g., by .profile)
        unset __HM_SESS_VARS_SOURCED
        . "${config.home.profileDirectory}/etc/profile.d/hm-session-vars.sh"

        # Source agenix-decrypted personal API keys if present (see age.secrets).
        if [ -f "${nickyApiKeysPath}" ]; then
          set -a
          . "${nickyApiKeysPath}"
          set +a
        fi
      '';
    };
    git = {
      enable = true;
      lfs = {
        enable = true;
      };
      # maintenance = {
      #   enable = true;
      # };
      #package = pkgs.git; # The git package to use. Use pkgs.gitFull to gain access to git send-email for instance. # Also for some features related to git-maintenance on git remotes used with ssh.
      settings.user.name = "Yannick Loth";
      settings.user.email = "727881+yannickloth@users.noreply.github.com";
    };
    # Let Home Manager install and manage itself.
    home-manager.enable = true;
    uv = {
      enable = true;
    };
    # Merged from the previous nicky-hm.nix config
    firefox = {
      enable = true;
      configPath = "${config.xdg.configHome}/mozilla/firefox";
      policies = {
        # Pre-98 behavior: opened files go to a temp dir; Downloads only on explicit save.
        StartDownloadsInTempDirectory = true;
      };
    };
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  systemd.user.services = {
    nestor-mount = {
      Unit = {
        Description = "Mount nestor NAS (Tailscale) via Rclone";
        # No After=network-online.target: that unit lives in the system
        # manager and is invisible to user units. Restart=on-failure below
        # retries until Tailscale is up.
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
      Service = {
        # Use full paths to be safe in systemd units
        ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p %h/nestor";
        ExecStart = ''
          ${pkgs.rclone}/bin/rclone mount nestor:/ /home/${config.home.username}/nestor \
          --vfs-cache-mode writes
        '';
        # fusermount3 from the Nix closure (not /usr/bin: wrong on NixOS).
        ExecStop = "${pkgs.fuse3}/bin/fusermount3 -u %h/nestor";
        Restart = "on-failure";
        RestartSec = "15s";
      };
    };

  };

  xdg.configFile."user-dirs.dirs".force = true;

  # XDG dirs live directly inside nicky's syncthing folder (/sync/yannick via
  # the ~/sync symlink), the same layout used for aeiuno (christine), sven and
  # aaron. KDE/Plasma and xdg-user-dirs pick these up; content is synced across
  # the laptops and replicated to nestor.
  xdg.userDirs = {
    createDirectories = false;
    enable = true;
    setSessionVariables = true; # keep legacy default
    desktop = "/home/nicky/sync/yannick/Desktop/";
    documents = "/home/nicky/sync/yannick/Documents/";
    download = "/home/nicky/sync/yannick/Downloads/";
    music = "/home/nicky/sync/yannick/Music/";
    pictures = "/home/nicky/sync/yannick/Pictures/";
    projects = "/home/nicky/sync/yannick/Projects/";
    publicShare = "/home/nicky/sync/yannick/Public/";
    templates = "/home/nicky/sync/yannick/Templates/";
    videos = "/home/nicky/sync/yannick/Videos/";
  };
}
