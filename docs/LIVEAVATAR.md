# LiveAvatar (June HR) in the Employee Discovery interview

The real-time avatar interview (`/discover/<invite-link>/avatar`) uses one avatar
and one architecture: **LiveAvatar FULL mode, in restricted mode, with the June HR
avatar**. There is no Simli avatar, no LITE mode, no voice-only mode and no
automatic fallback of any kind. If LiveAvatar cannot start, or drops mid-interview,
the page shows the reason and a **Try again** button. Answers are always saved, and
the text interview stays one link away.

The Employee Discovery V2 engine stays authoritative. It controls the four discovery
phases, WorkItems, transcript evidence, effort and frequency ranges, unknowns,
read-back and confirmation. Every spoken answer goes through the same durable
`POST /discover/messages` path as typed answers. Every word June says is either
text the engine wrote or a fixed line from the instructions file.

## Why FULL, restricted mode

| Need | How FULL restricted mode meets it |
| --- | --- |
| June's own face and voice | LiveAvatar renders and voices June HR, lip-synced |
| Natural listening | LiveAvatar runs the microphone, voice activity detection, transcription and barge-in |
| MJaDi decides every question | No `context_id` and no LLM settings are sent. LiveAvatar documents this as restricted mode: *"it will not respond to user input. User transcripts are still emitted"* |
| One simple pipeline | Browser ↔ LiveAvatar for media; browser ↔ Rails ↔ V2 engine for the conversation. There is no second speech-to-text or text-to-speech service |

LITE was rejected because it needs our own speech-to-text and text-to-speech in the
browser. That is a second media pipeline and gives no extra control, since the
engine is already authoritative in FULL restricted mode. A LiveAvatar Context, Voice
Agent or custom LLM was rejected because LiveAvatar's LLM would then answer the
employee, and nothing would capture WorkItems, evidence or completion.

## Turn-taking (browser, `frontend/src/employee/DiscoverAvatar.tsx`)

1. **Consent.** No session is minted, and no credits are used, until the employee
   agrees on the web consent screen.
2. **Greeting.** The microphone stays closed during the greeting, so "hello" is not
   taken as an answer. It opens as the first question starts.
3. **End of turn.** LiveAvatar sends the transcript once its voice detection hears
   the employee stop. The page then waits:
   - 1.4 s by default;
   - 3 s when the words end mid-thought (with "and", "but", "so", "just", a comma…);
   - 2.6 s when only a 1–2 word fragment was heard.

   Segments are merged into one answer (`mergeSegment`). A resent or cumulative
   transcript is never duplicated.
4. **Only real speech answers.** An answer is sent only after a transcript heard
   since June's latest question. Silence, fillers ("um") and silence artefacts
   ("Thanks for watching") are dropped, and so is June's own voice. So June never
   asks a new question unless the employee has actually responded.
5. **Carrying on after a pause.** If the employee keeps talking after their answer
   was sent, June waits until they finish before asking the next question. The
   extra words are kept as the start of their next answer. They are never sent on
   their own to a question the employee has not heard.
6. **Barge-in.** June stops when the employee talks over her for 0.45 s, or when a
   transcript arrives while she is speaking. A cough or a short "mm" does not cut
   her off. If June was interrupted but no words came through, she asks her
   question again after 2.5 s.
7. **Echo protection.** A "user" transcript of three or more words that matches
   what June just said (≥ 85 % of the words, during or up to 2.5 s after her speech)
   is dropped. It is her own voice reaching the microphone.
8. **While the engine works.** A neutral backchannel ("Mm-hm.") plays only if the
   next question takes more than 1.8 s, and never the same one twice in a row.
   No backchannel plays while the employee is talking. Speech during processing is
   handled as in step 5.
9. **No stuck turns.**
   - Each line June says resolves after it finishes. It also resolves if it never
     starts within 8 s, or runs past its length estimate, so a lost LiveAvatar event
     cannot hang the interview.
   - Requests time out after 20 s. Answers are retried idempotently with the same
     submission ID.
   - If the engine reports a failed turn, the saved answer is reprocessed once
     automatically (`POST /discover/messages {retry: true}`). If it fails again, the
     page shows "Try again".
   - After 60 s the page offers "Try again" or "Keep waiting".
10. **Guard.** If June ever says words the engine did not send, she is silenced at
   once and the same session carries on. Nothing switches mode or provider.
11. **Progress.** A four-step indicator shows the current phase: Your day, Regular
   work, Hidden effort, Time & confirm. It reads `interview_phase` from the engine
   state.

**Paused screen.** Pause (or End) shows *Continue with AI Avatar* and *Continue with
Text*. Text stops the LiveAvatar session and opens `/discover/<link>/chat`. That uses
the same employee session and saved conversation, and only reads, so nothing is
re-sent or asked twice.

Add `?debug=1` to see "LiveAvatar FULL" in the header and per-turn timings.

## Engine behaviour for spoken turns (`agent/app/employee_discovery_v2.py`)

Spoken answers are marked `input_mode: voice`, which means:

- **Evidence.** The answer is recorded as `TRANSCRIPT` evidence (Document 03).
- **Conversation memory.**
  - The question writer sees the last 12 messages, not 2.
  - It sees the last 10 questions asked (`questions_already_asked`).
  - It is told when the conversation moves to a new phase (`moving_to_new_phase`),
    so it bridges the topic change.
- **Core voice rules (`VOICE_CONDUCT`, cannot be overridden).**
  - React specifically to the answer, then ask one question.
  - Never repeat a question.
  - Ask for more when an answer is unclear or cut off.
- **Repetition guard.** A generated question that mostly overlaps one of the last
  6 is replaced by the plan's fixed wording (word overlap ≥ 0.75).
- **Sizing one item at a time.** Voice never gets the numbered multi-item sizing
  list, which cannot be spoken. Each activity is sized in one natural question
  that covers how often and how long.
- **No stall on a slow model.** The question writer has a 20 s timeout. If it fails,
  the planned topic's fixed wording is used. The text interview still raises and
  retries as before.

## Configurable interviewer instructions

**`agent/app/interviewer/instructions.yaml`** (version `mjadi-discovery-interviewer-2.2`, reviewed against Documents 00, 02, 03 and 04)
guides both what June asks and how. It is written from Documents 00, 02, 03 and 04.

| Section | Effect |
| --- | --- |
| `persona`, `style`, `voice_style` | How June sounds: reacting, building on earlier answers, varied openings, topic bridges, answering a direct question briefly |
| `phases.<anchor/inventory/invisible_work/size_close>` | Purpose and follow-up guidance for the current phase |
| `topics.<topic>` (**new**) | **What** to learn on each planned topic (`goal`) and what to build on in the answer (`listen_for`). Covers all ten topics: anchor, weekly, monthly, seasonal, the five invisible-work probes and AI use |
| `follow_ups` | Bounded contextual follow-ups: `explore` and `size_early`. The engine enforces the limits |
| `opening_questions`, `read_back`, `closing` | Fixed wording |
| `avatar` | Greeting, "welcome back", "say that again", "just a moment", backchannels and consent text. Read by Rails |

**What the file cannot change (enforced in code):**

- the deterministic plan, the four-phase order and the coverage rules;
- validation of generated wording: on plan and topic, one question, not a
  repeat, speakable;
- the WorkItem, evidence and fact-status contracts;
- completion, which needs explicit confirmation of the current read-back.

**Validation.** The agent re-reads the file on change. A file that fails validation
(schema, unknown topic, or text that tries to skip coverage, change completion, ask
for credentials, suggest automation, or cite management or peer views) is rejected
as a whole, and the built-in wording is used.

**Governance (Document 02 §15).**

- Bump `version` for every edit.
- Every turn records `<version>+<sha256 prefix>`.
- Material changes need the discovery benchmark and human sign-off.

## Configuration (root `.env`, read by Docker Compose)

| Variable | Needed | Meaning |
| --- | --- | --- |
| `LIVEAVATAR_API_KEY` | Yes | LiveAvatar dashboard → Developers |
| `LIVEAVATAR_AVATAR_ID` | Yes (unless sandbox) | The June HR avatar's ID |
| `LIVEAVATAR_SANDBOX` | Optional | `true` gives free ~1-minute sessions, but only with LiveAvatar's sandbox avatar (not June HR). Keep `false` for June |
| `LIVEAVATAR_VOICE_ID` | Optional | Voice override (default: June HR's own voice) |
| `LIVEAVATAR_LANGUAGE` | Optional | Language override (default: the employee's language) |
| `LIVEAVATAR_MAX_SESSION_DURATION_SECONDS` | Optional | Must not exceed your plan's limit |
| `LIVEAVATAR_VIDEO_QUALITY` | Optional | `very_high`, `high`, `medium` or `low` |
| `OPENAI_API_KEY` | Yes | The V2 engine (capture and question writing) |

`AVATAR_PROVIDER`, `LIVEAVATAR_MODE` and `SIMLI_*` are no longer read.

After changing `.env`, run `docker compose up -d --force-recreate rails frontend`.

## Server endpoints (employee web-session auth)

- **`GET /api/v1/public/discover/consent`** and **`POST /api/v1/public/discover/consent {version}`**:
  web consent, with the same effects as WhatsApp "YES".
- **`POST /api/v1/public/discover/voice/session`** mints one LiveAvatar FULL session
  token.
  - It also returns June's fixed lines and display name. The API key never leaves
    Rails.
  - Any request parameters (`liveavatar_mode`, `fallback`) are ignored.
  - Starting a session stops this employee's previous one.
  - If LiveAvatar refuses, it returns `503 {error, retryable: true}`, with
    LiveAvatar's reason.
  - If LiveAvatar is not configured, it returns `503 {retryable: false}`.
- **`POST /api/v1/public/discover/voice/session/stop`** is a backstop. It stops the
  session with the API key, so a closed tab does not keep spending credits.

## Tests (all mocked: no LiveAvatar or OpenAI session, no credits)

- `backend/spec/services/live_avatar/client_spec.rb` (WebMock) covers:
  - the FULL token body;
  - that no context or LLM field is sent;
  - that `LIVEAVATAR_MODE=LITE` is ignored;
  - errors and stop.
- `backend/spec/requests/api/v1/public/discover_voice_spec.rb` covers:
  - the FULL token and fixed texts;
  - that LITE and Simli requests are ignored;
  - the 503 refusal, the "not configured" response, the stop backstop and rate
    limiting.
- `frontend/e2e/liveavatar-renderer.spec.ts` runs in Node with a fake session. It
  covers the utterance queue, barge-in, echo drop, lost-event timeout, the guard,
  and disconnect.
- `frontend/e2e/liveavatar-page-mocked.spec.ts` drives the full page with every API
  mocked and a fake SDK. It blocks LiveAvatar, LiveKit, OpenAI and Simli. It covers:
  - the conversation;
  - consent;
  - fragments;
  - a lost response;
  - barge-in, the noise threshold, and the re-ask after an empty interrupt;
  - the guard;
  - the refusal with retry, and the drop with resume.

  Run it with `E2E_BASE_URL=http://localhost:5173 npx playwright test e2e/liveavatar-page-mocked.spec.ts`.
- `agent/tests/test_voice_conversation.py` covers:
  - topic guidance;
  - voice sizing without the numbered batch;
  - conversation context;
  - the near-repeat guard;
  - the fallback to fixed wording on a writer timeout.
- `agent/tests/test_interviewer_instructions.py` and `agent/tests/test_interviewer_follow_ups.py`
  cover file validation and the bounded follow-ups.

## Known limitations

- **Restricted mode and `repeat()` have not been tested live.** LiveAvatar's docs
  say restricted mode emits transcripts and "can only repeat pre-set phrases". They
  do not explicitly say that `avatar.speak_text` works without a context. This
  needs a live check.
- **Voice detection timing is LiveAvatar's.** There is no documented setting for it.
- **Echo protection relies on browser echo cancellation plus the transcript match.**
  Laptop speakers at high volume in a reverberant room can still leak audio, so
  headphones are recommended on the start screen.
- **Two model calls per turn.** Each answer goes through capture, then question
  writing. On `gpt-4.1-mini`, expect roughly 2–5 s between the end of an answer and
  June's next question. The backchannel covers the gap.
- **The old `GET /discover/voice/speech` endpoint (OpenAI TTS) is still on the
  server**, but the avatar page no longer uses it.
