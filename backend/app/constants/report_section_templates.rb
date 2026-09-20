# frozen_string_literal: true

# The section library a consultant picks from when adding their own sections to a
# report, before it ships.
#
# Why a library and not a blank box: the "add section" mechanism already existed
# (ReportSectionOverride action "add"), but a consultant was handed an empty
# textarea and no structure. The sections below are the ones a real strategy
# deliverable carries and an AI-generated report structurally cannot produce —
# they need judgement, not evidence:
#
#   * ASSUMPTIONS / LIMITATIONS — what we could not see. Only a human knows.
#   * RISKS — what could go wrong doing this. Requires having done it before.
#   * QUICK WINS — what to do in 90 days to build momentum and buy-in.
#   * BENCHMARKS — how this compares to peers. Requires outside knowledge.
#   * OPTIONS CONSIDERED — the roads not taken, and why. Shows rigour.
#   * IMPLEMENTATION — owners, sequencing, resourcing. Requires org knowledge.
#   * GOVERNANCE — who decides what, and at what cadence.
#
# Each scaffold is a starting skeleton, not boilerplate to be shipped as-is: it
# poses the questions the section must answer so a consultant fills in judgement
# rather than staring at a cursor.
module ReportSectionTemplates
  DEFINITIONS = [
    {
      "key" => "expert_conclusion",
      "title" => "The expert view",
      "purpose" => "Your own answer to the client's question, in your words. Leads the deliverable.",
      "anchor" => "executive_summary",
      "recommended" => true,
      "scaffold" => <<~TEXT
        ## What I'd tell them

        State the single most important conclusion in one sentence. Answer first —
        the reader should be able to stop after this line and still know what to do.

        ## Why I'm confident

        - The evidence that convinced you
        - What you have seen work elsewhere
        - What makes this company's case clear-cut

        ## What I'd watch

        The one thing that would change this advice.
      TEXT
    },
    {
      "key" => "assumptions_limitations",
      "title" => "Assumptions and limitations",
      "purpose" => "What this analysis could not see. Protects the client and your credibility.",
      "anchor" => "methodology",
      "recommended" => true,
      "scaffold" => <<~TEXT
        ## What we assumed

        - Assumption, and what it rests on
        - Assumption, and what it rests on

        ## What we could not see

        - Evidence that was unavailable, and how that bounds the findings
        - Departments or systems not covered in this round

        ## What would sharpen this

        The specific evidence that would most reduce uncertainty.
      TEXT
    },
    {
      "key" => "risks",
      "title" => "Risks and mitigations",
      "purpose" => "What could go wrong executing the recommendations, and how to de-risk it.",
      "anchor" => "recommendations",
      "recommended" => true,
      "scaffold" => <<~TEXT
        ## Execution risks

        **Risk.** What could go wrong, and how likely.
        *Mitigation.* The concrete step that reduces it.

        **Risk.** What could go wrong, and how likely.
        *Mitigation.* The concrete step that reduces it.

        ## The risk of doing nothing

        What compounds if this is deferred another two quarters.
      TEXT
    },
    {
      "key" => "quick_wins",
      "title" => "First 90 days",
      "purpose" => "Early victories that build momentum and sponsor buy-in before the big programme.",
      "anchor" => "roadmap",
      "recommended" => true,
      "scaffold" => <<~TEXT
        ## Do these first

        **Week 1–2.** The change that needs no budget and no new system.
        *Why first:* proves the finding is real and costs nothing to try.

        **Week 3–6.** The change that needs one owner and a decision.

        **Week 7–12.** The change that sets up the larger programme.

        ## What "working" looks like

        The measure you would check at day 90 to know it landed.
      TEXT
    },
    {
      "key" => "benchmarks",
      "title" => "How this compares",
      "purpose" => "Peer and sector context. Outside knowledge the evidence base cannot supply.",
      "anchor" => "signals",
      "recommended" => false,
      "scaffold" => <<~TEXT
        ## Against comparable operations

        Where this company sits versus peers of similar size and sector, on the
        one or two measures that matter most here.

        ## What good looks like

        The level a well-run operation of this shape achieves, and what it takes
        to get there.

        ## Where they are genuinely ahead

        Name it — a credible assessment is not a list of failures.
      TEXT
    },
    {
      "key" => "options_considered",
      "title" => "Options considered",
      "purpose" => "The roads not taken, and why. Shows the recommendation survived alternatives.",
      "anchor" => "recommendations",
      "recommended" => false,
      "scaffold" => <<~TEXT
        ## Option A — recommended

        What it is, what it costs, what it returns.

        ## Option B

        What it is, and the specific reason it loses to A here.

        ## Option C — do nothing

        The honest baseline. What it costs to stay as-is.
      TEXT
    },
    {
      "key" => "implementation",
      "title" => "Implementation plan",
      "purpose" => "Owners, sequencing, resourcing, milestones. Turns advice into a plan.",
      "anchor" => "roadmap",
      "recommended" => false,
      "scaffold" => <<~TEXT
        ## Sequencing

        What has to happen before what, and why that order.

        ## Owners and effort

        - **Workstream** — owner, rough effort, dependency
        - **Workstream** — owner, rough effort, dependency

        ## Milestones

        The three checkpoints where you would stop and reassess.
      TEXT
    },
    {
      "key" => "governance",
      "title" => "Governance",
      "purpose" => "Who decides what, at what cadence. The thing that makes plans survive month three.",
      "anchor" => "roadmap",
      "recommended" => false,
      "scaffold" => <<~TEXT
        ## Decision rights

        Who signs off on what, and the threshold at which it escalates.

        ## Cadence

        What gets reviewed weekly, monthly, quarterly — and by whom.

        ## What to measure

        The small number of measures worth reporting, and where they come from.
      TEXT
    },
    {
      "key" => "next_steps",
      "title" => "Next steps",
      "purpose" => "The explicit ask. What you want the client to do this week.",
      "anchor" => "roadmap",
      "recommended" => true,
      "scaffold" => <<~TEXT
        ## This week

        The single decision you are asking them to make, and who needs to be in
        the room to make it.

        ## What we need from you

        - Access, data or a named owner
        - The decision that unblocks everything else

        ## What happens then

        What the next phase looks like once that decision is made.
      TEXT
    }
  ].freeze

  KEYS = DEFINITIONS.map { |d| d["key"] }.freeze
  BY_KEY = DEFINITIONS.index_by { |d| d["key"] }.freeze
  RECOMMENDED = DEFINITIONS.select { |d| d["recommended"] }.freeze

  def self.find(key)
    BY_KEY[key.to_s]
  end
end
