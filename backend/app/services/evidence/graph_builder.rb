# frozen_string_literal: true

module Evidence
  class GraphBuilder
    def self.call(company:)
      new(company: company).call
    end

    def initialize(company:)
      @company = company
      @nodes = []
      @edges = []
      @seen = {}
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
        meta: meta
      }
      key
    end

    def add_edge(from, to, relation)
      return if from.blank? || to.blank?
      return unless @seen[from] && @seen[to]

      from_type, from_id = from.split(":", 2)
      to_type, to_id = to.split(":", 2)
      @edges << {
        type: relation,
        relation: relation,
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
          meta: { department: employee.department, role_title: employee.role_title }
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
        add_node(
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
      end
    end

    def add_patterns
      @company.patterns.find_each do |pattern|
        add_node(
          "pattern",
          pattern,
          label: pattern.title,
          meta: { status: pattern.status, confidence: pattern.try(:confidence) }
        )
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

    def coverage_stats
      counts = @nodes.group_by { |n| n[:type] }.transform_values(&:size)
      {
        node_count: @nodes.size,
        edge_count: @edges.size,
        by_type: counts,
        signals: counts["signal"].to_i,
        supported_edges: @edges.count { |e| e[:type].to_s.in?(%w[supports derived_from extracted_from aggregates_into]) },
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
