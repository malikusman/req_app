# frozen_string_literal: true

module Evidence
  class GraphBuilder
    SUPPORTED_RELATIONS = %w[supports derived_from extracted_from aggregates_into].freeze

    def self.call(company:)
      new(company: company).call
    end

    def initialize(company:)
      @company = company
      @nodes = []
      @edges = []
      @seen = {}
      @signal_employee_ids = Hash.new { |h, k| h[k] = [] }
      @share_weights = Hash.new(0)
    end

    def call
      add_employees
      add_conversations_and_messages
      add_media
      add_documents
      add_signals
      add_patterns
      add_recommendations
      add_findings
      add_outreaches
      add_employee_cluster_edges
      enrich_employee_evidence_counts!

      {
        nodes: @nodes,
        edges: @edges,
        coverage: coverage_stats
      }
    end

    private

    def add_node(type, record, label:, meta: {})
      key = "#{type}:#{record.id}"
      return key if @seen[key]

      @seen[key] = true
      @nodes << {
        id: record.id,
        key: key,
        type: type,
        record_id: record.id,
        label: label,
        department: meta[:department],
        confidence: meta[:confidence] || meta[:strength],
        source_type: meta[:source_type] || meta[:document_type] || meta[:signal_type],
        evidence_count: meta[:evidence_count],
        meta: meta
      }
      key
    end

    def add_edge(from, to, relation, weight: 1, meta: {})
      return if from.blank? || to.blank?
      return unless @seen[from] && @seen[to]

      from_type, from_id = from.split(":", 2)
      to_type, to_id = to.split(":", 2)
      @edges << {
        type: relation,
        relation: relation,
        weight: weight.to_i.clamp(1, 20),
        label: meta[:label],
        excerpt: meta[:excerpt],
        from: { type: from_type, id: from_id.to_i },
        to: { type: to_type, id: to_id.to_i },
        from_key: from,
        to_key: to
      }
    end

    def add_employees
      @company.employees.find_each do |employee|
        add_node(
          "employee",
          employee,
          label: employee.display_name.presence || employee.phone_e164,
          meta: {
            department: employee.department,
            role_title: employee.role_title,
            evidence_count: 0
          }
        )
      end
    end

    def add_conversations_and_messages
      @company.conversations.includes(:messages, :employee).find_each do |conversation|
        conv_id = add_node(
          "conversation",
          conversation,
          label: "Conversation ##{conversation.id}",
          meta: { status: conversation.status }
        )
        emp_id = "employee:#{conversation.employee_id}"
        add_edge(emp_id, conv_id, "has_conversation") if @seen[emp_id]

        conversation.messages.each do |message|
          msg_id = add_node(
            "message",
            message,
            label: message.body.to_s.truncate(80).presence || "#{message.message_type} message",
            meta: { direction: message.direction, message_type: message.message_type }
          )
          add_edge(conv_id, msg_id, "contains")
        end
      end
    end

    def add_media
      @company.media_attachments.find_each do |media|
        media_id = add_node(
          "media",
          media,
          label: "#{media.attachment_type} ##{media.id}",
          meta: { status: media.status, attachment_type: media.attachment_type }
        )
        add_edge("message:#{media.message_id}", media_id, "has_media") if media.message_id && @seen["message:#{media.message_id}"]
        add_edge("conversation:#{media.conversation_id}", media_id, "has_media") if media.conversation_id && @seen["conversation:#{media.conversation_id}"]
        add_edge("employee:#{media.employee_id}", media_id, "uploaded") if media.employee_id && @seen["employee:#{media.employee_id}"]
      end
    end

    def add_documents
      @company.documents.find_each do |document|
        doc_id = add_node(
          "document",
          document,
          label: document.filename,
          meta: {
            status: document.status,
            document_type: document.try(:document_type),
            sensitivity: document.try(:sensitivity)
          }
        )
        add_edge("employee:#{document.employee_id}", doc_id, "uploaded") if document.employee_id && @seen["employee:#{document.employee_id}"]
        add_edge("conversation:#{document.conversation_id}", doc_id, "attached") if document.conversation_id && @seen["conversation:#{document.conversation_id}"]
      end
    end

    def add_signals
      @company.company_signals.find_each do |signal|
        sig_key = add_node(
          "signal",
          signal,
          label: signal.label,
          meta: {
            signal_type: signal.signal_type,
            status: signal.status,
            strength: signal.strength,
            departments: Array(signal.try(:departments))
          }
        )

        Array(signal_source_excerpts(signal)).each do |item|
          emp_id = item["employee_id"].presence || item[:employee_id]
          next if emp_id.blank?

          emp_key = "employee:#{emp_id}"
          next unless @seen[emp_key]

          excerpt = (item["excerpt"] || item[:excerpt]).to_s.presence
          add_edge(sig_key, emp_key, "extracted_from", meta: { excerpt: excerpt&.truncate(200) })
          @signal_employee_ids[signal.id] << emp_id.to_i
        end
      end
    end

    def signal_source_excerpts(signal)
      meta = signal.metadata
      return [] unless meta.is_a?(Hash)

      raw = meta["source_excerpts"] || meta[:source_excerpts] || []
      Array(raw).map { |item| item.respond_to?(:stringify_keys) ? item.stringify_keys : item }
    end

    def add_patterns
      @company.patterns.find_each do |pattern|
        pat_key = add_node(
          "pattern",
          pattern,
          label: pattern.title,
          meta: {
            status: pattern.status,
            confidence: pattern.try(:confidence),
            departments: Array(pattern.try(:departments))
          }
        )

        Array(pattern.linked_signal_ids).each do |signal_id|
          sig_key = "signal:#{signal_id}"
          add_edge(sig_key, pat_key, "aggregates_into") if @seen[sig_key]
        end
      end
    end

    def add_recommendations
      @company.recommendations.find_each do |recommendation|
        rec_id = add_node(
          "recommendation",
          recommendation,
          label: recommendation.title,
          meta: { status: recommendation.status, priority: recommendation.priority }
        )
        Array(recommendation.try(:related_pattern_ids)).each do |pattern_id|
          add_edge("pattern:#{pattern_id}", rec_id, "supports") if @seen["pattern:#{pattern_id}"]
        end
        Array(recommendation.try(:related_signal_ids)).each do |signal_id|
          add_edge(rec_id, "signal:#{signal_id}", "derived_from") if @seen["signal:#{signal_id}"]
        end
      end
    end

    def add_findings
      ReportReviewFinding
        .joins(report_review: :report)
        .where(reports: { company_id: @company.id })
        .find_each do |finding|
          finding_id = add_node(
            "finding",
            finding,
            label: finding.finding_type,
            meta: {
              severity: finding.severity,
              disposition: finding.disposition,
              publishable: finding.publishable?
            }
          )
          if finding.target_type.present? && finding.target_id.present?
            target_key = "#{finding.target_type.underscore}:#{finding.target_id}"
            add_edge(finding_id, target_key, "targets") if @seen[target_key]
          end
        end
    end

    def add_outreaches
      ::ReviewerOutreach.where(company_id: @company.id).find_each do |outreach|
        outreach_id = add_node(
          "outreach",
          outreach,
          label: outreach.purpose,
          meta: { status: outreach.status, channel: outreach.channel }
        )
        add_edge("employee:#{outreach.employee_id}", outreach_id, "recipient") if outreach.employee_id && @seen["employee:#{outreach.employee_id}"]
        add_edge(outreach_id, "conversation:#{outreach.conversation_id}", "via") if outreach.conversation_id && @seen["conversation:#{outreach.conversation_id}"]
      end
    end

    def add_employee_cluster_edges
      @signal_employee_ids.each_value do |employee_ids|
        employee_ids.uniq.combination(2).each do |a, b|
          pair = [a, b].sort
          @share_weights[pair] += 1
        end
      end

      @share_weights.each do |(a, b), weight|
        add_edge("employee:#{a}", "employee:#{b}", "shares_signal", weight: weight)
      end

      @company.employees.where.not(department: [nil, ""]).group_by { |e| e.department.to_s.strip.downcase }.each do |dept, employees|
        next if dept.blank? || employees.size < 2

        employees.map(&:id).combination(2).each do |a, b|
          pair = [a, b].sort
          next if @share_weights.key?(pair)

          add_edge(
            "employee:#{a}",
            "employee:#{b}",
            "same_department",
            weight: 1,
            meta: { label: employees.first.department }
          )
        end
      end
    end

    def enrich_employee_evidence_counts!
      counts = Hash.new(0)
      @edges.each do |edge|
        next unless edge[:type] == "extracted_from" && edge.dig(:to, :type) == "employee"

        counts[edge.dig(:to, :id)] += 1
      end

      @nodes.each do |node|
        next unless node[:type] == "employee"

        count = counts[node[:id]]
        node[:evidence_count] = count
        node[:meta] = (node[:meta] || {}).merge(evidence_count: count)
      end
    end

    def coverage_stats
      counts = @nodes.group_by { |n| n[:type] }.transform_values(&:size)
      supported = @edges.count { |e| e[:type].to_s.in?(SUPPORTED_RELATIONS) }
      signals_linked = @edges.select { |e| e[:type].to_s.in?(%w[extracted_from aggregates_into]) }
                             .flat_map { |e| [e[:from], e[:to]] }
                             .select { |ref| ref[:type] == "signal" }
                             .map { |ref| ref[:id] }
                             .uniq
                             .size

      {
        node_count: @nodes.size,
        edge_count: @edges.size,
        by_type: counts,
        signals: counts["signal"].to_i,
        signals_linked: signals_linked,
        supported_edges: supported,
        shares_signal_edges: @edges.count { |e| e[:type] == "shares_signal" },
        same_department_edges: @edges.count { |e| e[:type] == "same_department" },
        employees: counts["employee"].to_i,
        conversations: counts["conversation"].to_i,
        messages: counts["message"].to_i,
        media: counts["media"].to_i,
        documents: counts["document"].to_i,
        patterns: counts["pattern"].to_i,
        recommendations: counts["recommendation"].to_i,
        findings: counts["finding"].to_i,
        outreaches: counts["outreach"].to_i
      }
    end
  end
end
