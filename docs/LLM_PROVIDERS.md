# LLM providers: OpenAI (prod) ↔ LM Studio (local)

Switch by editing `.env` only, then:

```bash
docker compose up -d --force-recreate rails sidekiq langgraph
```

Shared pgvector size is **768** for both profiles (EmbeddingGemma native; OpenAI `text-embedding-3-small` with `dimensions=768`).

## Recommended OpenAI stack (cheaper + good)

| Role | Env var | Model | Why |
|------|---------|-------|-----|
| Default / discovery / vision | `OPENAI_MODEL`, `OPENAI_VISION_MODEL` | **`gpt-4.1-mini`** | Strong instruction following + JSON; ~2–3× `gpt-4o-mini` cost but better extraction quality |
| Docs Analyze fast path | `DOCS_MODEL_FAST` | **`gpt-4.1-mini`** | Per-document specialist extract |
| Docs Analyze reasoning | `DOCS_MODEL_REASONING` | **`o4-mini`** | Cheap o-series reasoning for clarifications / synthesis; avoid `o3` / `gpt-4o` unless quality gate fails |
| Embeddings | `EMBEDDING_MODEL` | **`text-embedding-3-small`** @ 768-d | Cheap + matches local EmbeddingGemma dim |

**Do not use for routine docs Analyze:** `o3` (~2× `o4-mini`), `gpt-4o` / `gpt-4.1` full (much higher $/token), or flagship GPT-5 tiers.

### List prices (OpenAI API, ~Jul 2026, USD per 1M tokens)

| Model | Input | Output |
|-------|------:|-------:|
| gpt-4o-mini | $0.15 | $0.60 |
| gpt-4.1-mini | $0.40 | $1.60 |
| o4-mini | $1.10 | $4.40 |
| o3 | $2.00 | $8.00 |
| gpt-4o | $2.50 | $10.00 |
| text-embedding-3-small | ~$0.02 | — |

Official refs: [o4-mini](https://developers.openai.com/api/docs/models/o4-mini), [gpt-4.1-mini](https://developers.openai.com/api/docs/models/gpt-4.1-mini).

### Estimated cost per company run (GulfLink-sized: ~5 portal docs)

Rough token sketch for one **Docs Analyze** + light Rails summarize/embed (not WhatsApp interviews):

| Stage | Model | Approx tokens | Cost |
|-------|-------|---------------|------|
| Per-doc extract (×5) | gpt-4.1-mini | ~40k in / ~8k out | ~$0.03 |
| Reasoning / questions | o4-mini | ~30–60k in / ~8–20k out (+ reasoning tokens) | ~$0.10–$0.25 |
| Embeddings (chunks) | text-embedding-3-small | ~50–100k | &lt;$0.01 |
| Web research summarize | gpt-4.1-mini | small | ~$0.01 |
| **Total Analyze** | | | **~$0.15–$0.40** |

Add later:

| Extra | Typical |
|-------|---------|
| Full WhatsApp discovery (few employees) | +$0.20–$1.00 depending on turns |
| Report PDF | mostly template (near $0 LLM) |
| Re-Analyze after clarifications | often cheaper than first full run |

**Budget tip:** keep `DOCS_MODEL_REASONING=o4-mini` with `reasoning_effort` low/medium if you add that knob later; escalate to `o3` only for hard companies. Ultra-cheap alternate: `gpt-4o-mini` for fast + `o4-mini` for reasoning (~30–40% lower on extract).

## Production / OpenAI

Leave `OPENAI_BASE_URL` unset. Set a real `OPENAI_API_KEY` and the PROFILE A model IDs from [`.env.example`](../.env.example).

## Local / LM Studio

1. In [LM Studio](https://lmstudio.ai/), download and load:
   - Chat: [google/gemma-4-12b-qat](https://lmstudio.ai/models/google/gemma-4-12b-qat)
   - Embeddings: EmbeddingGemma 300M (exact id from LM Studio)
2. Start the **Local Server** on port **1234**.
3. Confirm IDs: `curl http://localhost:1234/v1/models`
4. In `.env`, use PROFILE B from [`.env.example`](../.env.example).
5. Recreate `rails`, `sidekiq`, `langgraph`.

Smoke from a container:

```bash
docker compose exec rails curl -sS http://host.docker.internal:1234/v1/models
```

Then: company portal → upload docs → **Analyze documents**.

## Notes

- Whisper / vision still use the chat base URL; locally they may mock or fail unless the local server supports those routes — that is expected.
- After switching embedding providers, re-run **Analyze** so chunks are re-embedded (migration nulls old 1536-d vectors).
- `OPENAI_JSON_MODE=false` is recommended for LM Studio (Gemma often rejects `response_format: json_object`).
- Local Gemma may need `OPENAI_MAX_TOKENS≥2500` because reasoning tokens burn the completion budget before `content` is written.
