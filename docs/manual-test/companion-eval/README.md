# Companion local eval (LM Studio)

## Prerequisites
1. LM Studio running on port **1234** with chat model loaded (e.g. `google/gemma-4-12b-qat`).
2. Docker Compose `rails` up.
3. Prefer **PROFILE B** env for the run (`ALLOW_MOCKS=0`). You can override via `docker compose exec -e` without changing committed `.env`.

## Run

```bash
docker compose exec -e OPENAI_BASE_URL=http://host.docker.internal:1234/v1 \
  -e OPENAI_API_KEY=lm-studio \
  -e OPENAI_MODEL=google/gemma-4-12b-qat \
  -e DOCS_MODEL_FAST=google/gemma-4-12b-qat \
  -e OPENAI_JSON_MODE=false \
  -e OPENAI_MAX_TOKENS=2500 \
  -e ALLOW_MOCKS=0 \
  -e LIVE=1 -e WRITE=1 \
  rails bundle exec rails scenario:companion
```

Artifacts:
- [RESULTS.json](./RESULTS.json)
- [OBSERVATIONS.md](./OBSERVATIONS.md)

## Scenarios
C1 casual, C2 ask, C3 tools, C7 no-interview-feel, C4 share, C5 promote-yes, C6 addendum phrase, W1 web casual.

Layer A = structural routing asserts. Layer B = local-model judge (`score >= 0.6`, no interview leak). Overall requires structural pass + judge pass rate ≥ 70%.
