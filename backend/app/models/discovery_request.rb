class DiscoveryRequest < ActiveSupport::CurrentAttributes
  attribute :admitting, :submission, :deadline_at, :turn_identity, :base_revision

  def self.remaining!
    # Other callers (documents, consultant tools, speech) retain their own limits.
    return Float::INFINITY unless deadline_at
    remaining = deadline_at - Time.current
    raise Langgraph::UnavailableError.new('discovery_deadline_exceeded', code: 'deadline_exceeded') if remaining <= 0
    remaining
  end
end
