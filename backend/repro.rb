REDIS.del("openai:circuit_open"); REDIS.del("openai:error_window")
puts "breaker cleared, open?=#{OpenaiCircuitBreaker.open?}"
c = Company.find_by(slug: "nimbus-trading")
e = c.employees.order(:id).first
conv = e.conversations.order(:id).last
puts "employee=#{e.display_name} conv=#{conv.id} status=#{conv.status} qcount=#{conv.question_count}"
t0 = Time.current
result = Discovery::ProcessTurnService.call(
  conversation: conv, employee: e,
  user_message: "Most of my day is raising LPOs in Zoho and checking proforma invoices.",
  defer_on_failure: false
)
puts "turn took #{(Time.current - t0).round(1)}s"
puts "delayed=#{result['delayed'].inspect} assistant=#{result['assistant_message'].to_s.truncate(90)}"
puts "breaker after: open?=#{OpenaiCircuitBreaker.open?}"
