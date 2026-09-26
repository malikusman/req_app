# frozen_string_literal: true

# One piece of work, in one role, that costs the company something. See the
# create_findings migration for why this exists alongside company signals.
class Finding < ApplicationRecord
  STATUSES = %w[draft approved hidden merged].freeze
  BASES = %w[discovery discovery_partial deep_dive consultant].freeze
  CONFIDENCES = %w[high medium low].freeze
  FREQUENCY_UNITS = %w[per_day per_week per_month per_quarter per_year per_event].freeze
  DURATION_UNITS = %w[minutes hours days].freeze
  EFFORT_TYPES = %w[active waiting mixed unknown].freeze

  belongs_to :company
  belongs_to :employee, optional: true
  belongs_to :conversation, optional: true
  belongs_to :merged_into, class_name: "Finding", optional: true
  has_many :merged_findings, class_name: "Finding", foreign_key: :merged_into_id, dependent: :nullify

  validates :source_key, :area, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :basis, inclusion: { in: BASES }
  validates :confidence, inclusion: { in: CONFIDENCES }
  validates :effort_type, inclusion: { in: EFFORT_TYPES }
  validates :frequency_unit, inclusion: { in: FREQUENCY_UNITS }, allow_nil: true
  validates :duration_unit, inclusion: { in: DURATION_UNITS }, allow_nil: true

  belongs_to :reviewed_by, class_name: "ConsultantUser", optional: true

  scope :live, -> { where.not(status: %w[hidden merged]) }

  validate :merge_target_is_a_live_sibling
  validate :consultant_effort_is_coherent

  # Hours are worked out here and nowhere else, from the consultant's figures when
  # they corrected them and the interview's otherwise — whenever either changes.
  before_save :compute_annual_hours, if: :effort_changing?

  EFFORT_COLUMNS = %w[frequency_min frequency_max frequency_unit duration_min duration_max duration_unit
                      effort_type consultant_effort].freeze

  UNIT_WORDS = {
    "per_day" => "a day", "per_week" => "a week", "per_month" => "a month",
    "per_quarter" => "a quarter", "per_year" => "a year", "per_event" => "each time"
  }.freeze

  def hours?
    annual_hours_min.present? && annual_hours_max.present?
  end

  # What a client would read: the consultant's wording where they gave one, the
  # interview's otherwise. The machine text itself is never changed.
  def display_title = consultant_title.presence || title.presence || area
  def display_what_happens_now = consultant_what_happens_now.presence || what_happens_now
  def display_friction = consultant_friction.presence || friction

  # Two cases may not reach a client until a consultant has looked: a finding about
  # the only person in a role identifies them, and one carrying the same figures as
  # another from the same interview is probably that work counted twice.
  def needs_review? = status == "draft" && (single_occupant_role || possible_duplicate_of_id.present?)

  def possible_duplicate_of_id = evidence.is_a?(Hash) ? evidence["possible_duplicate_of"] : nil

  def effort_corrected? = consultant_effort.present?

  # The figures hours are computed from: the consultant's where they corrected
  # them, the interview's otherwise.
  def effective_effort
    if effort_corrected?
      frequency = consultant_effort["frequency"] || {}
      duration = consultant_effort["duration"] || {}
      {
        frequency_min: frequency["min"], frequency_max: frequency["max"], frequency_unit: frequency["unit"],
        duration_min: duration["min"], duration_max: duration["max"], duration_unit: duration["unit"],
        effort_type: consultant_effort["effort_type"].presence || effort_type
      }
    else
      {
        frequency_min: frequency_min, frequency_max: frequency_max, frequency_unit: frequency_unit,
        duration_min: duration_min, duration_max: duration_max, duration_unit: duration_unit,
        effort_type: effort_type
      }
    end
  end

  def effective_effort_type = effective_effort[:effort_type]

  # What a client reads under "how often" and "how long": the employee's words,
  # unless a consultant corrected the figures — then the corrected figures, since
  # the words no longer describe them.
  def display_frequency
    return frequency_as_said unless effort_corrected?

    e = effective_effort
    phrase(e[:frequency_min], e[:frequency_max], UNIT_WORDS[e[:frequency_unit]])
  end

  def display_duration
    return duration_as_said unless effort_corrected?

    e = effective_effort
    unit = e[:duration_unit].to_s
    unit = unit.singularize if e[:duration_max].to_f == 1.0
    phrase(e[:duration_min], e[:duration_max], unit)
  end

  def compute_annual_hours
    hours = Findings::AnnualHours.call(**effective_effort)
    self.annual_hours_min = hours.min
    self.annual_hours_max = hours.max
    self.hours_basis = hours.basis.merge("reason" => hours.reason, "corrected" => (effort_corrected? || nil)).compact
    hours
  end

  # Accepts the controller's params or a plain hash; keeps only a coherent shape.
  # Numbers the consultant typed arrive as strings.
  def consultant_effort=(value)
    raw = value.respond_to?(:to_unsafe_h) ? value.to_unsafe_h : (value || {})
    raw = raw.deep_stringify_keys
    side = lambda do |part|
      next nil unless part.is_a?(Hash)

      low = number(part["min"])
      high = number(part["max"]) || low
      unit = part["unit"].presence
      next nil if low.nil? && unit.nil?

      { "min" => low, "max" => high, "unit" => unit }
    end
    effort = { "frequency" => side.call(raw["frequency"]), "duration" => side.call(raw["duration"]),
               "effort_type" => raw["effort_type"].presence }.compact
    # Not `super`: Active Record generates the column's own writer lazily, so on a
    # fresh process there may be nothing to call yet.
    self[:consultant_effort] = effort
  end

  private

  def effort_changing?
    EFFORT_COLUMNS.any? { |column| will_save_change_to_attribute?(column) }
  end

  def phrase(min, max, words)
    return nil if min.nil? || words.blank?

    fmt = ->(n) { (n.to_f % 1).zero? ? n.to_i.to_s : n.to_f.to_s }
    range = min.to_f == max.to_f || max.nil? ? fmt.call(min) : "#{fmt.call(min)}–#{fmt.call(max)}"
    "#{range} #{words}"
  end

  def number(value)
    return nil if value.blank?

    Float(value)
  rescue ArgumentError, TypeError
    Float::NAN
  end

  def consultant_effort_is_coherent
    return if consultant_effort.blank?

    { "frequency" => FREQUENCY_UNITS, "duration" => DURATION_UNITS }.each do |key, units|
      part = consultant_effort[key]
      next if part.nil?

      unless units.include?(part["unit"])
        errors.add(:base, "How #{key == 'frequency' ? 'often' : 'long'} needs a unit")
        next
      end
      low, high = part["min"], part["max"]
      if [low, high].any? { |n| n.is_a?(Float) && n.nan? } || [low, high].compact.any? { |n| n <= 0 }
        errors.add(:base, "How #{key == 'frequency' ? 'often' : 'long'} must be a positive number")
      elsif low && high && low > high
        errors.add(:base, "How #{key == 'frequency' ? 'often' : 'long'}: the lower figure comes first")
      end
    end
    type = consultant_effort["effort_type"]
    errors.add(:base, "Unknown kind of work") if type && !EFFORT_TYPES.include?(type)
  end

  def merge_target_is_a_live_sibling
    return if merged_into_id.blank?

    target = merged_into
    if target.nil? || target.company_id != company_id
      errors.add(:merged_into, "must be a finding for the same company")
    elsif target.id == id
      errors.add(:merged_into, "cannot be the finding itself")
    elsif target.status == "merged"
      errors.add(:merged_into, "is itself merged into another finding")
    end
  end
end
