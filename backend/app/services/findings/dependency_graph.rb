# frozen_string_literal: true

module Findings
  # Links between findings — "this must be addressed before that" — must never run
  # in a circle, or no order of work satisfies them. Shared by the drafted links
  # (Findings::DraftDependencies) and the consultant's own (Finding validation).
  module DependencyGraph
    module_function

    # edges: { finding id => ids it depends on }. True when adding from → to would
    # close a loop, i.e. `to` already depends, directly or not, on `from`.
    def loop?(edges, from, to)
      seen = Set.new
      stack = [to]
      while (node = stack.pop)
        return true if node == from
        next unless seen.add?(node)

        stack.concat(Array(edges[node]))
      end
      false
    end
  end
end
