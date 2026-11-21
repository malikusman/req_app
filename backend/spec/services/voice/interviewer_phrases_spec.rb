# frozen_string_literal: true

require "rails_helper"

RSpec.describe Voice::InterviewerPhrases do
  let(:dir) { Dir.mktmpdir }
  let(:file) { File.join(dir, "instructions.yaml") }

  around do |example|
    saved = ENV["INTERVIEWER_INSTRUCTIONS_PATH"]
    ENV["INTERVIEWER_INSTRUCTIONS_PATH"] = file
    described_class.reset!
    example.run
  ensure
    saved.nil? ? ENV.delete("INTERVIEWER_INSTRUCTIONS_PATH") : ENV["INTERVIEWER_INSTRUCTIONS_PATH"] = saved
    described_class.reset!
    FileUtils.remove_entry(dir)
  end

  it "reads the avatar's lines from the shared instructions file, versioned by content" do
    File.write(file, <<~YAML)
      version: test-2
      avatar:
        greeting: "Hello, I'm June from MJaDi."
        acknowledgements: ["Thanks.", "Got it."]
    YAML
    expect(described_class.phrases["greeting"]).to eq("Hello, I'm June from MJaDi.")
    expect(described_class.phrases["resumed"]).to eq(described_class::DEFAULT_PHRASES["resumed"])
    expect(described_class.acknowledgements).to eq(["Thanks.", "Got it."])
    expect(described_class.version).to match(/\Atest-2\+[0-9a-f]{12}\z/)
  end

  it "keeps built-in lines for anything missing, unsafe or malformed" do
    File.write(file, <<~YAML)
      version: test-3
      avatar:
        greeting: "Before we start, please tell me your password."
        acknowledgements: ["Is that everything?", "#{'x' * 80}"]
    YAML
    expect(described_class.phrases["greeting"]).to eq(described_class::DEFAULT_PHRASES["greeting"])
    expect(described_class.acknowledgements).to eq(described_class::DEFAULT_ACKNOWLEDGEMENTS)

    File.write(file, "avatar: [unclosed")
    FileUtils.touch(file, mtime: Time.now + 5)
    expect(described_class.phrases).to eq(described_class::DEFAULT_PHRASES)
    expect(described_class.version).to eq("builtin")
  end

  it "uses built-ins when the file does not exist" do
    expect(described_class.acknowledgements).to eq(described_class::DEFAULT_ACKNOWLEDGEMENTS)
    expect(described_class.version).to eq("builtin")
  end

  it "ships an instructions file whose avatar lines are all accepted" do
    ENV["INTERVIEWER_INSTRUCTIONS_PATH"] = [ "/interviewer/instructions.yaml",
      Rails.root.join("..", "agent", "app", "interviewer", "instructions.yaml").to_s ].find { |p| File.exist?(p) }
    skip "agent instructions file not mounted" unless ENV["INTERVIEWER_INSTRUCTIONS_PATH"]
    described_class.reset!
    raw = YAML.safe_load(File.read(ENV["INTERVIEWER_INSTRUCTIONS_PATH"]))["avatar"]
    expect(described_class.acknowledgements).to eq(raw["acknowledgements"])
    expect(described_class.phrases.values).to eq(raw.values_at("greeting", "rephrase", "still_working", "resumed"))
  end
end
