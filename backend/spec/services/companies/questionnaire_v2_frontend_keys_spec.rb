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
  let(:source) { File.read(Rails.root.join("..", "frontend", "src", "lib", "questionnaireV2Config.ts")) }

  let(:fields_with_types) do
    source.scan(/\{\s*id:\s*'([^']+)',\s*type:\s*'([^']+)'/).map { |id, type| [id, type] }
  end

  let(:static_ids) { fields_with_types.select { |_id, type| type == "static" }.map(&:first).sort }
  let(:frontend_keys) { fields_with_types.reject { |_id, type| type == "static" }.map(&:first) }

  # tier: is not positionally adjacent to id:/type: in the source (it comes
  # after label/helper/options/groups, varies per field), so it can't be
  # captured in the same regex pass as fields_with_types above. Instead,
  # find each field object's start offset via id:/type:, then slice the
  # source between consecutive starts to scan that one field's full object
  # text for its own tier. A field with no tier: at all is essential by
  # convention (asserted, not assumed, by this spec).
  let(:frontend_tiers_by_key) do
    matches = source.to_enum(:scan, /\{\s*id:\s*'([^']+)',\s*type:\s*'([^']+)'/).map { Regexp.last_match }
    matches.each_with_index.to_h do |match, index|
      id = match[1]
      start_offset = match.begin(0)
      end_offset = index + 1 < matches.size ? matches[index + 1].begin(0) : source.length
      chunk = source[start_offset...end_offset]
      tier_match = chunk.match(/tier:\s*'([^']+)'/)
      [id, tier_match ? tier_match[1] : "essential"]
    end
  end

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

  it "matches the backend registry's tier for every key exactly" do
    mismatches = Companies::QuestionnaireV2Config::FIELD_IDS.filter_map do |key|
      backend_tier = Companies::QuestionnaireV2Config::TIERS_BY_KEY[key].to_s
      frontend_tier = frontend_tiers_by_key[key]
      next if frontend_tier == backend_tier

      "#{key}: backend=#{backend_tier.inspect} frontend=#{frontend_tier.inspect}"
    end
    expect(mismatches).to eq([]), "tier mismatches between backend and frontend: #{mismatches.inspect}"
  end
end