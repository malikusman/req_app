# frozen_string_literal: true

require "rails_helper"

# Cross-check guard for frontend/backend transcription drift.
#
# There is no frontend test runner in this repo, so this Ruby spec reads the
# TypeScript config directly and asserts its stored keys exactly equal the
# backend registry. If the two sets drift apart (a key added on one side but
# not the other, or a key typo'd on either side), answers silently fail to
# persist — the controller slices saves to FIELD_IDS — or the completion
# maths silently disagrees. This spec fails loudly with the specific missing
# or extra keys so nobody has to bisect a silent gap.
#
# `static` fields (msg_*) are informational display copy, not stored answers,
# so they are excluded from the comparison explicitly and asserted as a fixed
# set below rather than filtering incidentally. Keep this spec; it is cheap
# and it is the only automated guard of its kind we have.
RSpec.describe "frontend questionnaireV2Config keys vs Companies::QuestionnaireV2Config::FIELD_IDS" do
  let(:fields_with_types) do
    source = File.read(Rails.root.join("..", "frontend", "src", "lib", "questionnaireV2Config.ts"))
    source.scan(/\{\s*id:\s*'([^']+)',\s*type:\s*'([^']+)'/).map { |id, type| [id, type] }
  end

  let(:static_ids) { fields_with_types.select { |_id, type| type == "static" }.map(&:first).sort }
  let(:frontend_keys) { fields_with_types.reject { |_id, type| type == "static" }.map(&:first) }

  it "parses the frontend config and finds the stored fields" do
    expect(fields_with_types.size).to be >= 45
  end

  it "documents the static (non-stored) display fields explicitly" do
    expect(static_ids).to eq(%w[msg_info_intro msg_process_documents msg_time_intro])
  end

  it "has no duplicate frontend keys" do
    expect(frontend_keys.uniq).to eq(frontend_keys)
  end

  it "matches the backend registry exactly: no missing and no extra keys" do
    missing = Companies::QuestionnaireV2Config::FIELD_IDS - frontend_keys
    extra = frontend_keys - Companies::QuestionnaireV2Config::FIELD_IDS
    expect(missing).to eq([]), "keys in backend FIELD_IDS but missing from frontend config: #{missing.inspect}"
    expect(extra).to eq([]), "keys in frontend config but not in backend FIELD_IDS: #{extra.inspect}"
    expect(frontend_keys.size).to eq(Companies::QuestionnaireV2Config::FIELD_IDS.size)
  end
end