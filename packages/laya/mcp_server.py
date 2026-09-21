"""Laya MCP server — System 1 decision engine over streamable HTTP.

Exposes the local `laya` package to MCP clients (opencode) as a shared,
GPU-resident service. The Router preloads the English and multilingual
checkpoints in a background thread, so the HTTP endpoint and tool listing are
available immediately; tool calls wait for the load to finish.

Environment:
  LAYA_MCP_HOST   bind address          (default 127.0.0.1)
  LAYA_MCP_PORT   bind port             (default 8765)
  LAYA_DEVICE     cuda | cpu | mps      (default: auto)
  LAYA_MAX_LEN    context window, tokens (default: checkpoint value, 512/1024).
                  The encoders are 8k-native, but the decision heads were trained
                  on 512/1024-token windows, so quality beyond that is unvalidated.
"""
from __future__ import annotations

import logging
import os
import sys
import threading
from typing import Any, Dict, List, Optional, Union

logging.basicConfig(
    level=logging.INFO,
    stream=sys.stderr,
    format="%(asctime)s laya-mcp %(levelname)s %(message)s",
)
log = logging.getLogger("laya-mcp")

import laya  # noqa: E402
from laya import presets  # noqa: E402
from mcp.server.mcpserver import MCPServer  # noqa: E402

State = Union[str, Dict[str, Any], List[Any]]

_server = MCPServer(
    name="laya",
    title="Laya System 1 decision engine",
    version=laya.__version__,
    instructions=(
        "Fast, non-autoregressive decision engine with calibrated probabilities. "
        "Use `predict` for custom typed questions, `route` to inspect checkpoint "
        "selection, and the preset tools (triage, email, guard, moderation) for "
        "common workflows. Prefer these over guessing for classification, "
        "urgency/scoring, and yes-no judgments."
    ),
)

_router: Optional["laya.Router"] = None
_ready = threading.Event()
_load_error: Optional[str] = None


def _apply_max_len(router: "laya.Router") -> None:
    """Override each loaded checkpoint's context window from LAYA_MAX_LEN.

    `max_len` is a checkpoint setting, not an architecture limit: both encoders
    are 8k-native. It is clamped so the question/option head always fits.
    """
    raw = os.environ.get("LAYA_MAX_LEN")
    if not raw:
        return
    try:
        requested = int(raw)
    except ValueError:
        log.warning("ignoring invalid LAYA_MAX_LEN=%r", raw)
        return
    for name in router.loaded:
        agent = router.load(name)
        floor = int(agent.cfg.get("head_max_len", 192)) + 16
        applied = max(requested, floor)
        agent.cfg["max_len"] = applied
        if applied != requested:
            log.info("max_len for %s: %d (raised from %d to fit the head)", name, applied, requested)
        else:
            log.info("max_len for %s: %d", name, applied)
        # Rotary positions have no fixed table, so the encoder accepts more than
        # its stated max — but that is extrapolation past the trained window.
        enc_max = getattr(agent.model.encoder.config, "max_position_embeddings", None)
        if enc_max and applied > enc_max:
            log.warning(
                "max_len for %s: %d exceeds the encoder's %d positions (rotary "
                "extrapolation; quality unvalidated)",
                name, applied, enc_max,
            )


def _preload() -> None:
    global _router, _load_error
    try:
        device = os.environ.get("LAYA_DEVICE") or None
        log.info("preloading Router (english + multilingual, device=%s)", device or "auto")
        # Note: the Router(preload=...) constructor arg only takes a bool; a list
        # is truthy and would load *every* checkpoint. Preload the two we serve.
        _router = laya.Router(device=device)
        _router.preload(["english", "multilingual"])
        _apply_max_len(_router)
        log.info("Router ready: %s", _router.loaded)
    except Exception as exc:  # keep serving; tool calls surface the error
        _load_error = f"{type(exc).__name__}: {exc}"
        log.exception("Router preload failed")
    finally:
        _ready.set()


def _get_router() -> "laya.Router":
    _ready.wait()
    if _router is None:
        raise RuntimeError(f"Laya model failed to load: {_load_error}")
    return _router


@_server.tool()
def predict(
    state: State,
    questions: Dict[str, Any],
    model: Optional[str] = None,
) -> Dict[str, Any]:
    """Answer typed questions about `state` in a single forward pass.

    `state` is text, a JSON object, or a conversation turn list. `questions`
    maps question id -> definition:
      {"type": "choice", "instructions": "...", "criteria": {"optA": "...", ...}}
      {"type": "score",  "instructions": "...", "criteria": ["lvl0", "lvl1", ...]}
      {"type": "noul",   "instructions": "..."}
    `model` optionally pins a checkpoint (english | multilingual | typed-decisions);
    otherwise the router picks one by detected language/script.
    """
    return _get_router().predict(state, questions, model=model)


@_server.tool()
def route(
    state: State,
    questions: Optional[Dict[str, Any]] = None,
    model: Optional[str] = None,
    task: Optional[str] = None,
    lang: Optional[str] = None,
) -> Dict[str, Any]:
    """Decide which checkpoint would handle `state`, and why, without running it."""
    return dict(_get_router().route(state, questions, model=model, task=task, lang=lang))


def _run_preset(state: State, questions: Dict[str, Any], model: Optional[str]) -> Dict[str, Any]:
    return _get_router().predict(state, questions, model=model)


@_server.tool()
def triage(state: State, model: Optional[str] = None) -> Dict[str, Any]:
    """Customer-support triage preset (intent, urgency, frustration, churn risk)."""
    return _run_preset(state, presets.triage_questions(), model)


@_server.tool()
def email(
    state: State,
    categories: Optional[Dict[str, str]] = None,
    model: Optional[str] = None,
) -> Dict[str, Any]:
    """Inbound-email preset (category, spam, phishing, urgency, needs reply)."""
    return _run_preset(state, presets.email_questions(categories), model)


@_server.tool()
def guard(state: State, model: Optional[str] = None) -> Dict[str, Any]:
    """LLM input-guardrail preset (jailbreak, prompt injection, sensitive data, harm)."""
    return _run_preset(state, presets.guard_questions(), model)


@_server.tool()
def moderation(state: State, model: Optional[str] = None) -> Dict[str, Any]:
    """Content-moderation preset (toxicity, harassment, threat, spam, severity)."""
    return _run_preset(state, presets.moderation_questions(), model)


@_server.tool()
def detect_language(text: str) -> Dict[str, Any]:
    """Detect script and language of `text` (the router's routing signal)."""
    return laya.detect_language(text)


def main() -> None:
    host = os.environ.get("LAYA_MCP_HOST", "127.0.0.1")
    port = int(os.environ.get("LAYA_MCP_PORT", "8765"))
    threading.Thread(target=_preload, name="laya-preload", daemon=True).start()
    log.info("serving MCP on http://%s:%d/mcp", host, port)
    _server.run(
        transport="streamable-http",
        host=host,
        port=port,
        streamable_http_path="/mcp",
        stateless_http=True,
    )


if __name__ == "__main__":
    main()
