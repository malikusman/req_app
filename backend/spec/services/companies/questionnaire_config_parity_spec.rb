# frozen_string_literal: true

require "rails_helper"

# Cross-check guard against frontend/backend drift.
#
# The questionnaire is defined twice: question text and options in the TypeScript
# config, storage keys and tiers in Companies::QuestionnaireConfig. They have to
# agree, and nothing at runtime notices when they don't — the controller slices
# saves to the backend whitelist, so a key that exists only on the frontend is
# simply thrown away on save, silently, and the answer is lost.
#
# There is no frontend test runner here, so this reads the TypeScript directly.
RSpec.describe "questionnaireOptions.ts vs Companies::QuestionnaireConfig" do
  # Relative to the repo root in CI, and a read-only mount under Docker. If
  # neither resolves, fail rather than skip — a guard nobody notices has stopped
  # running is worse than no guard.
  let(:config_path) do
    [Rails.root.join("..", "frontend", "src", "lib", "questionnaireOptions.ts"),
     Pathname.new("/frontend/src/lib/questionnaireOptions.ts")].find(&:exist?)
  end

  let(:source) do
    raise "questionnaireOptions.ts not found — mount ./frontend into the container" unless config_path

    File.read(config_path)
  end

  # Matches a field object's opening `{ id: '…', type: '…'`. The option groups
  # inside the category matrix carry `id:` followed by `label:`, so they do not
  # match and do not need excluding by name.
  let(:field_matches) do
    source.to_enum(:scan, /\{\s*id: '([^']+)',\s*\n\s*type: '([^']+)'/).map { Regexp.last_match }
  end

  let(:fields) do
    field_matches.each_with_index.map do |match, index|
      finish = index + 1 < field_matches.size ? field_matches[index + 1].begin(0) : source.length
      chunk = source[match.begin(0)...finish]
      {
        id: match[1],
        type: match[2],
        tier: chunk[/tier: '([^']+)'/, 1],
        with_other: chunk.include?("withOther: true"),
        with_detail: chunk.include?("withDetail: true"),
        show_when: chunk.include?("showWhen:")
      }
    end
  end

  let(:questions) { fields.reject { |f| f[:type] == "static" } }

  it "stores exactly the keys the backend knows about" do
    expect(questions.map { |f| f[:id] }).to match_array(Companies::QuestionnaireConfig::FIELD_IDS)
  end

  it "presents them in the same order the backend records" do
    expect(questions.map { |f| f[:id] }).to eq(Companies::QuestionnaireConfig::FIELD_IDS)
  end

  it "agrees on which questions are Essential" do
    frontend = questions.select { |f| f[:tier] == "essential" }.map { |f| f[:id] }

    expect(frontend).to match_array(Companies::QuestionnaireConfig::ESSENTIAL_KEYS)
  end

  it "agrees on every tier, not only Essential" do
    frontend = questions.to_h { |f| [f[:id], f[:tier].to_s] }
    backend = Companies::QuestionnaireConfig::TIERS_BY_KEY.transform_values(&:to_s)

    expect(frontend).to eq(backend)
  end

  # A question that offers "Other" on screen but has no sidecar key in the backend
  # whitelist drops whatever the user typed into it.
  it "agrees on which questions capture free text for Other" do
    frontend = questions.select { |f| f[:with_other] }.map { |f| "#{f[:id]}_other" }

    expect(frontend).to match_array(Companies::QuestionnaireConfig::SIDECAR_KEYS)
  end

  it "agrees on which questions capture a per-selection detail" do
    frontend = questions.select { |f| f[:with_detail] }.map { |f| "#{f[:id]}_detail" }

    expect(frontend).to match_array(Companies::QuestionnaireConfig::DETAIL_KEYS)
  end

  # Both sides compute visibility; if only one of them knows a question is
  # conditional, the percent and the rendering disagree.
  it "agrees on which questions are conditional" do
    frontend = questions.select { |f| f[:show_when] }.map { |f| f[:id] }

    expect(frontend).to match_array(Companies::QuestionnaireConfig::CONDITIONAL.keys)
  end

  it "covers all eight steps and 45 stored answers" do
    expect(questions.size).to eq(45)
    expect(Companies::QuestionnaireConfig::STEP_COUNT).to eq(8)
  end

  # The product was renamed; the questionnaire addresses the company by name in
  # several questions, and those are the most visible strings in the whole app.
  it "never addresses the customer by the old brand" do
    expect(source).not_to include("Worktruth")
  end
end
