# Observability: real OTLP tracing into Arato.ai

> **This is a Day 8 lesson**, taught with Arato.ai and Agenta.ai — not part of the
> Day 4 metrics exercises. It lives in Module 2 because it is shaped like a Module 2
> lesson (single provider, ordinary pass=good assertions), not because it is taught
> alongside them.

Every other lesson in this module asks "did the model answer well?" This one
asks a different question: once a system like this is *deployed*, what is it
doing — how slow, how many tokens, which requests are erroring? That's
observability, and the standard for it is OpenTelemetry (OTel).

## What's real here

- **Trace/span IDs, latency, token counts** — genuinely measured from a real
  Groq API call, not simulated.
- **The prompt hash** — a real SHA-256 of the actual prompt, computed at
  request time.
- **The span leaving the process** — genuine, wire-compatible OTLP over HTTP,
  POSTed to [Arato.ai](https://www.arato.ai) if you set
  `OTEL_EXPORTER_OTLP_ENDPOINT`/`ARATO_API_KEY` in `.env` (both optional —
  sample output below shows what happens either way).

## No SDK, still real OTLP

This repo has no `package.json` anywhere (see `CLAUDE.md`), so
`@opentelemetry/exporter-trace-otlp-proto` isn't available. Rather than fake it,
`otlp.mjs` hand-encodes the protobuf — about 70 lines covering the four wire
types this one message needs. What goes over the network is the same bytes the
official SDK would send.

That is worth understanding rather than skipping past. OTLP is not magic: a span
is a protobuf message with a trace ID, a span ID, two timestamps, and a bag of
attributes. Read `otlp.mjs` and the format stops being a black box.

Two things Arato is strict about, both learned by probing the live endpoint:

1. **It only speaks protobuf.** Send OTLP/JSON and you get
   `500 {"error": "invalid wire type 4 at offset 236"}` — it tries to parse your
   JSON as protobuf and fails partway in.
2. **It dispatches on the instrumentation scope name.** The scope must start with
   `openinference.instrumentation.` or you get
   `400 {"error": "Unknown span type: <your-scope>"}`. `langsmith`, `agno`, and
   `pydantic-ai` are all rejected; this lesson uses
   `openinference.instrumentation.openai`.

Attribute names follow the OpenInference conventions (`llm.model_name`,
`llm.token_count.prompt`, `llm.input_messages.0.message.content`, …) — those are
what Arato reads to populate its UI.

## Why privacy is part of this, not an afterthought

`provider.mjs` never logs the raw prompt text — only its SHA-256 hash. This
mirrors a real production pattern: telemetry is itself a place user data can
leak, so it gets the same "don't log what you don't need" treatment as any
other data sink.

## Run it

```bash
npx promptfoo@latest eval -c modules/02-advanced-eval/observability/promptfooconfig.yaml
```

Sample output (Arato unset):
```
{
  "span": "llm.chat.completion",
  "trace_id": "4bf92f3577b34da6a3ce929d0e0e4736",
  "span_id": "00f067aa0ba902b7",
  "model": "llama-3.3-70b-versatile",
  "duration_ms": 412,
  "tokens": { "prompt_tokens": 12, "completion_tokens": 34, "total_tokens": 46 },
  "prompt.sha256": "8f3a2b1c..."
}
[arato] skipped — OTEL_EXPORTER_OTLP_ENDPOINT/ARATO_API_KEY not set
```

With a real Arato account, take both values from **Observe → your dashboard →
"Monitor With Arato"** and add them to `.env`:

```env
OTEL_EXPORTER_OTLP_ENDPOINT=https://api.arato.ai/opentelemetry/<your-project>
ARATO_API_KEY=ar-...
```

The endpoint already contains your project slug. Don't append `/v1/traces` —
`provider.mjs` does that. The last line then becomes:

```
[arato] OTLP 200 trace_id=054d11ec990cdcf906d7d4e9af2ae647
```

Copy that `trace_id` and find it in the Arato UI. **Do that at least once.** A
`200` proves the request was accepted, not that the span was stored the way you
meant — and the whole reason this lesson exists is that "it returned 200" and
"it worked" are different claims.

### Ingested is not the same as visible

Arato dashboards are **built, not automatic**. Send perfectly good spans to a
project with no dashboard querying them and you will see nothing at all — which
looks exactly like a broken integration and is not one.

That is worth sitting with for a second, because it is the whole lesson in
miniature. Three different things have to be true before a number reaches your
eyes, and they fail independently:

1. the app emits the span,
2. the backend accepts and stores it,
3. some view actually queries it.

"I don't see it" tells you one of the three broke, not which. This is the same
class of mistake as reading a green test suite that asserts nothing.

Build a dashboard against these — they're what `provider.mjs` sends:

| Field | Value |
|---|---|
| `service.name` | `break-into-ai-testing` (or your `OTEL_SERVICE_NAME`) |
| instrumentation scope | `openinference.instrumentation.openai` |
| span name | `llm.chat.completion` |
| `openinference.span.kind` | `LLM` |
| `llm.model_name` | `llama-3.3-70b-versatile` |
| `llm.provider` / `llm.system` | `groq` |
| `llm.token_count.prompt` / `.completion` / `.total` | integers |
| `input.value` / `output.value` | prompt/response, or their hash when `LOG_RAW_PROMPTS` is off |

### The privacy trade-off is a switch, and it has a cost

By default the message-content attributes are **not** your text — they're
`sha256:<hash> (len=N)`. That keeps the telemetry sink from becoming a copy of every
prompt your users typed.

It also means Arato's UI shows you hashes instead of conversations. That is the real
tension in production observability, and it's worth naming out loud in class: the tool is
more useful the more it knows, and more dangerous for exactly the same reason. Flip it
when you need to read the conversations back:

```env
LOG_RAW_PROMPTS=true
```

For a live demo you probably want it on — hashes make a dull dashboard. For anything
touching real user traffic, the default is the default for a reason.

## Why MediBot/FinanceBot don't have any of this

Module 1's bots call Groq directly via Promptfoo's built-in `groq:` provider
— there's no code of ours in that path to instrument. This lesson swaps in a
*custom* provider specifically so there's somewhere to put that
instrumentation. In a real deployment, your own API layer is that somewhere.

> Extension lesson — not part of the original `how-to-test-ai` day-03-promptfoo-advanced
> curriculum. Taught on **Day 8** (Advanced Red Teaming, SDLC Testing + Arato.ai &
> Agenta.ai).
