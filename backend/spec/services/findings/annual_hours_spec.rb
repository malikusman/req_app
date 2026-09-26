# frozen_string_literal: true

require "rails_helper"

RSpec.describe Findings::AnnualHours do
  def hours(freq, freq_unit, dur, dur_unit, effort_type: "active", freq_max: nil, dur_max: nil)
    described_class.call(frequency_min: freq, frequency_max: freq_max, frequency_unit: freq_unit,
                         duration_min: dur, duration_max: dur_max, duration_unit: dur_unit,
                         effort_type: effort_type)
  end

  it "turns every morning, forty minutes to an hour, into a yearly range" do
    result = hours(1, "per_day", 40, "minutes", dur_max: 60)
    # 240 working days x 40-60 minutes = 160-240 hours
    expect([result.min, result.max]).to eq([160, 240])
  end

  it "handles a weekly volume with a per-item time" do
    # Fifty CVs a week, ten minutes each: 48 weeks x 500 minutes = 400 hours.
    result = hours(50, "per_week", 10, "minutes")
    expect([result.min, result.max]).to eq([400, 400])
  end

  it "counts a duration in days as eight-hour working days" do
    # Two days of reconciliation every month.
    result = hours(1, "per_month", 2, "days")
    expect([result.min, result.max]).to eq([190, 195])
  end

  it "rounds outward so a range never implies precision a conversation cannot give" do
    result = hours(2, "per_week", 25, "minutes", freq_max: 3, dur_max: 35)
    # 48 x 2 x 25 / 60 = 40 ; 48 x 3 x 35 / 60 = 84
    expect([result.min, result.max]).to eq([40, 85])
  end

  it "never counts waiting as effort" do
    result = hours(15, "per_week", 3, "days", effort_type: "waiting")
    expect(result.hours?).to be(false)
    expect(result.reason).to eq("waiting is not effort")
  end

  it "gives no figure when either half is words only" do
    expect(hours(nil, nil, 30, "minutes").hours?).to be(false)
    expect(hours(1, "per_day", nil, nil).hours?).to be(false)
  end

  it "gives no figure for per-event work with no yearly volume" do
    expect(hours(nil, "per_event", 120, "minutes").reason).to include("per-event")
  end

  it "rejects units it does not understand rather than guessing" do
    expect(hours(1, "per_fortnight", 30, "minutes").hours?).to be(false)
  end

  it "states the basis it used" do
    expect(hours(1, "per_day", 30, "minutes").basis).to include("working_days" => 240, "hours_per_day" => 8)
  end
end
