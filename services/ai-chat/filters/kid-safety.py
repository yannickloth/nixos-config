"""Kid-safety gate for Open WebUI.

Runs server-side on every chat turn:
  - inlet(): inspects the user's question before it reaches the model.
  - outlet(): inspects the model's reply and swaps unsafe content.

Source of truth: services/ai-chat/filters/kid-safety.py (in git). It is
seeded into the Open WebUI database by the open-webui-seed-gates systemd
service, which Open WebUI reads at request time.
"""

BLOCKED_SUBJECTS = (
    "bomb", "explosive", "weapon", "gun", "pistol", "rifle",
    "drug", "cocaine", "marijuana", "weed", "heroin", "meth",
    "suicide", "self-harm", "kill myself", "cutting myself",
    "porn", "pornography", "sexual", "nude", "naked",
    "hate speech", "nazi", "racist",
    "poison", "how to hurt someone", "make a weapon",
)

SAFE_REPLY = (
    "That's not something I can help with. "
    "Want to talk about your favorite games, space, animals, or school subjects instead?"
)


def _contains_blocked(text):
    t = (text or "").lower()
    return any(b in t for b in BLOCKED_SUBJECTS)


def inlet(request):
    body = request.get("body", {})
    messages = body.get("messages", [])
    text = " ".join(m.get("content", "") for m in messages if m.get("role") == "user")
    if _contains_blocked(text):
        return {
            "messages": [{"role": "assistant", "content": SAFE_REPLY}],
            "finish": True,
        }
    return body


def outlet(request):
    body = request.get("body", {})
    messages = body.get("messages", [])
    if not messages:
        return body
    if _contains_blocked(messages[-1].get("content", "")):
        messages[-1]["content"] = SAFE_REPLY
    return body
