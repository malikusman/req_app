# Pilot checklist

For running Mjadi with a real client: before the first invite, while interviews
run, and before the report goes out. Each item says where to check it.

## Before inviting anyone

- [ ] **The model is the production one.** `OPENAI_MODEL=gpt-4.1-mini` with a real
      `OPENAI_API_KEY`, set for `rails`, `sidekiq` and `langgraph`. Local models are
      for development only.
- [ ] **Background jobs are running.** Sidekiq processes spoken answers, builds
      findings when an interview ends, and marks interviews abandoned
      (`mark_abandoned_conversations`, hourly). Nothing about voice or findings
      works without it.
- [ ] **The interview passes its test set.** `python scripts/interview_replay.py`
      in the agent container: expect 7–8 of 9 personas to pass, with zero capture
      fallbacks. Run `rails demo:company_interviews` once, open the demo company's
      Findings page and check the hours look like what the fact sheets say.
- [ ] **Company settings** (platform → company):
  - voice and uploads on (`discovery_multimodal_enabled`)
  - Reports tab → "Signals & patterns pages" set as agreed with Masood
    (appendix by default)
- [ ] **A consultant is assigned.** Findings and reports go through them; without
      one, nothing is reviewed before approval.
- [ ] **Employees are added with the right channel.** "Browser only" or
      "WhatsApp + browser" sends the email invite with the voice option. Check
      each email address — the link is personal and works once.
- [ ] **Try it yourself first.** Take one interview by voice on a phone and on a
      laptop, in Chrome and Safari, with a real microphone. Allow the microphone
      when asked; if it is blocked the page says so and typing still works.

## While interviews run

Platform → Operations → **Interviews** shows every company's interviews as
counts only. Look at it daily. The flags mean:

| Flag | What to do |
|---|---|
| In progress but quiet for over a day | Nudge the employee from the company's Employees page. After 72 hours of silence it is marked abandoned; what they said still counts, as partial findings. |
| Answers were not recorded | The recording step is failing — check the model key and the agent logs. The conversation carries on, but those answers give no findings. |
| Interviews ended without covering the role | They stalled or hit the question limit. Read one transcript (consultant view) to see why. |
| Only N of M findings have hours | People are not giving how often / how long. A consultant can correct figures on the Findings page. |
| Spoken answers failed to transcribe | Check the model key and that the upload reached storage (MinIO). |
| Findings waiting for consultant review | A role held by one person, or a probable double count. The consultant decides on the Findings page. |

## Before the report goes to the client

- [ ] **The consultant has reviewed the findings**: approved, merged the same
      work described twice, reworded anything that reads as a quote, corrected
      figures where the interview mis-heard.
- [ ] **Regenerate after the review.** The report is a snapshot of the findings
      when it was generated.
- [ ] **The report checks pass.** Consultant → report → Submit step shows them;
      platform approval refuses while a "Must fix" stands. Overriding needs a
      written reason and is logged — use it only for a genuine false positive.
- [ ] **Read the executive brief end to end.** Four pages; it is what the owner
      forwards.

## After

- Rotate any API key that was pasted into a chat or shared outside the
  environment it belongs to.
- Note what Masood and the client corrected — each correction is a case for the
  interview test set.
