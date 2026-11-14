# frozen_string_literal: true

require "rails_helper"

# The onboarding form is defined twice: question text and options in
# frontend/src/lib/onboardingFields.ts, and what may be stored in
# Companies::OnboardingFields. Nothing at runtime notices when they drift — the
# backend drops a key it doesn't know and refuses an option it doesn't list, so a
# client's answer would be lost or rejected. There is no frontend test runner
# here, so this reads the TypeScript directly.
RSpec.describe "onboardingFields.ts vs Companies::OnboardingFields" do
  let(:config_path) do
    [Rails.root.join("..", "frontend", "src", "lib", "onboardingFields.ts"),
     Pathname.new("/frontend/src/lib/onboardingFields.ts")].find(&:exist?)
  end

  let(:source) do
    raise "onboardingFields.ts not found — mount ./frontend into the container" unless config_path

    File.read(config_path)
  end

  let(:fields) do
    matches = source.to_enum(:scan, /\{\s*id: '([^']+)',\s*\n\s*type: '([^']+)'/).map { Regexp.last_match }
    matches.each_with_index.map do |match, index|
      finish = index + 1 < matches.size ? matches[index + 1].begin(0) : source.length
      chunk = source[match.begin(0)...finish]
      options_text = chunk[/options: \[(.*?)\]/m, 1]
      {
        id: match[1],
        type: match[2],
        with_other: chunk.include?("withOther: true"),
        options: options_text&.scan(/'([^']*)'/)&.flatten
      }
    end
  end

  let(:backend) { Companies::OnboardingFields }

  it "stores exactly the keys the backend accepts, in the same order" do
    expect(fields.map { |f| f[:id] }).to eq(backend::FIELD_IDS)
  end

  it "agrees on which fields capture free text for Other" do
    frontend = fields.select { |f| f[:with_other] }.map { |f| "#{f[:id]}_other" }
    expect(frontend).to match_array(backend::OTHER_KEYS)
  end

  # Options written out on the frontend must be exactly the backend's, plus
  # "Other" where the field has it and "Not sure" where unknown is allowed.
  it "offers the same options for every fixed-choice field" do
    fields.each do |field|
      definition = backend::BY_KEY[field[:id]]
      next unless definition[:options] && field[:options]

      expected = definition[:options].dup
      expected << backend::OTHER if definition[:with_other]
      expected << backend::NOT_SURE unless definition[:no_unknown]
      expect(field[:options]).to eq(expected), "#{field[:id]} options differ"
    end
  end

  it "asks nothing Doc 07 rules out of onboarding" do
    banned = /revenue|turnover|budget|pain point|bottleneck|readiness|outcome|anything else|timeline/i
    expect(source.scan(/label: '([^']*)'/).flatten.grep(banned)).to be_empty
  end
end
