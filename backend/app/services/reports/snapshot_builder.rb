# frozen_string_literal: true

module Reports
  class SnapshotBuilder
    def self.call(company:, delta:)
      new(company: company, delta: delta).call
    end

    def initialize(company:, delta:)
      @company = company
      @delta = delta
    end

    def call
      docs_first = docs_oriented?
      intel = Intelligence::SnapshotBuilder.call(company: @company)

      snapshot = base_snapshot(docs_first, intel)
      apply_narrative!(snapshot)
      # Roadmap is LLM-written when available, else derived from recommendation
      # priority — so the section is present regardless of the narrative writer.
      snapshot["roadmap"] ||= deterministic_roadmap(snapshot)
      snapshot
    end

    private

    def base_snapshot(docs_first, intel)
      {
        "generated_at" => Time.current.iso8601,
        "report_kind" => docs_first ? "baseline" : "discovery",
        "docs_first_phase" => docs_first,
        "company" => {
          "name" => @company.display_name || @company.name,
          "locale" => @company.locale,
          "engagement_mode" => @company.engagement_mode,
          "website_url" => clean_website(@company.try(:website_url)),
          "profile" => @company.company_profile.slice(
            "industry", "sub_industry", "size_band", "region", "country",
            "annual_revenue_band", "business_goals", "org_departments"
          ).merge("website_url" => clean_website(@company.try(:website_url))).compact
        },
        "readiness" => {
          "score" => @company.report_readiness_score,
          "breakdown" => @company.report_readiness_breakdown
        },
        "participation" => intel["participation"],
        "department_coverage" => Array(intel["department_coverage"]),
        "situation" => situation_json(docs_first),
        "signals" => signals_json,
        "patterns" => patterns_json,
        "implications" => implications_json,
        "recommendations" => recommendations_json,
        "delta_from_previous" => @delta,
        "executive_summary" => executive_summary(docs_first),
        "sections" => ReportSections::DEFINITIONS,
        "supporting_media" => supporting_media_json,
        "supporting_documents" => supporting_documents_json,
        "knowledge_base" => knowledge_base_json,
        "client_stack" => client_stack_json,
        "tools_catalog" => tools_catalog_json,
        "agentic_ideas" => agentic_ideas_json,
        "agent_activity" => agent_activity_json,
        "narrative" => nil,
        "roadmap" => nil
      }
    end

    # Light-touch attribution: which specialist discovery agents actually ran,
    # from message agent_id (domain_<dept> / process / technical / strategic /
    # compliance). Read-only over existing data — no new plumbing.
    def agent_activity_json
      counts = Message.joins(conversation: :employee)
                      .where(employees: { company_id: @company.id })
                      .where.not(agent_id: [nil, ""])
                      .group(:agent_id)
                      .count
      counts.map { |agent_id, turns| { "agent_id" => agent_id, "role" => agent_role_label(agent_id), "turns" => turns } }
            .sort_by { |a| -a["turns"] }
    rescue StandardError => e
      Rails.logger.warn("[Reports::SnapshotBuilder] agent_activity skipped: #{e.class}: #{e.message}")
      []
    end

    def agent_role_label(agent_id)
      id = agent_id.to_s
      if id.start_with?("domain_")
        "Domain specialist (#{id.sub('domain_', '').tr('_', ' ')})"
      else
        { "process" => "Process specialist", "technical" => "Technical specialist",
          "strategic" => "Strategic specialist", "compliance" => "Compliance specialist" }.fetch(id, id.humanize)
      end
    end

    # Enrich the deterministic snapshot with an LLM-written narrative when
    # available. The deterministic prose stays as the honest fallback and as the
    # source the writer is grounded on.
    def apply_narrative!(snapshot)
      narrative = NarrativeWriter.call(company: @company, snapshot: snapshot)
      return unless narrative

      snapshot["narrative"] = narrative

      # Cover subtitle / one-read summary prefer the pyramid governing thought.
      if narrative["executive_summary"].present?
        snapshot["executive_summary"] = narrative["executive_summary"]
      end

      snapshot["roadmap"] = narrative["roadmap"] if narrative["roadmap"].present?

      # Override each implication's "so what" with the LLM statement when it
      # clearly maps to the same pattern; otherwise keep the deterministic one.
      statements = narrative["implications"].to_h { |i| [i["pattern_title"].to_s.downcase, i["statement"]] }
      Array(snapshot["implications"]).each do |imp|
        match = statements[imp["title"].to_s.downcase]
        imp["statement"] = match if match.present?
      end
    end

    # Deterministic Now/Next/Later derived from recommendation priority — the
    # honest fallback when the LLM narrative writer is unavailable.
    def deterministic_roadmap(snapshot)
      recs = Array(snapshot["recommendations"])
      return nil if recs.empty?

      bucket = ->(pri) { recs.select { |r| r["priority"].to_s.downcase == pri } }
      now = bucket.call("high")
      later = bucket.call("low")
      nxt = recs - now - later # medium + anything unlabeled

      to_items = ->(list) { list.first(4).map { |r| { "title" => r["title"], "rationale" => r["description"].to_s.truncate(140).presence } } }
      roadmap = { "now" => to_items.call(now), "next" => to_items.call(nxt), "later" => to_items.call(later) }
      roadmap.values.any?(&:any?) ? roadmap : nil
    end

    # Documents-mode companies stay docs-oriented even if a contact was seeded for Q&A.
    def docs_oriented?
      @company.engagement_mode == "documents" || @company.docs_first_phase?
    end

    def signals_json
      @company.company_signals.order(strength: :desc).map do |s|
        {
          "id" => s.id,
          "label" => s.label,
          "strength" => s.strength,
          "departments" => s.departments,
          "signal_type" => s.signal_type,
          "evidence_count" => s.evidence_count,
          "multimodal_evidence" => Array(s.metadata.fetch("multimodal_evidence", [])).first(5),
          "source_excerpts" => normalize_excerpts(s.metadata.fetch("source_excerpts", [])).first(3)
        }
      end
    end

    def patterns_json
      signals_by_id = @company.company_signals.index_by(&:id)
      @company.patterns.order(confidence: :desc).map do |p|
        linked = Array(p.linked_signal_ids).filter_map { |id| signals_by_id[id.to_i] }
        {
          "id" => p.id,
          "title" => p.title,
          "description" => p.description,
          "confidence" => p.confidence,
          "departments" => Array(p.departments).presence || linked.flat_map { |s| Array(s.departments) }.uniq,
          "linked_signal_ids" => Array(p.linked_signal_ids),
          "linked_signal_labels" => linked.map(&:label),
          "linked_signal_types" => linked.map(&:signal_type).uniq,
          "evidence_count" => linked.sum { |s| s.evidence_count.to_i }
        }
      end
    end

    def recommendations_json
      recs = @company.recommendations.published.visible_to_company.to_a
      signals_by_id = @company.company_signals.index_by(&:id)
      stack_names = client_stack_json.map { |s| s["name"].to_s.downcase }

      # First pass: raw evidence weight per recommendation (real data only).
      raw_impacts = recs.map do |r|
        linked = Array(r.related_signal_ids).filter_map { |id| signals_by_id[id.to_i] }
        weight = linked.sum { |s| s.strength.to_f } + 0.15 * linked.sum { |s| s.evidence_count.to_i }
        # Fall back to the priority tier when a rec has no linked signals, so a
        # bare "high" rec still lands high rather than at zero.
        weight = [weight, priority_floor(r.priority)].max
        weight
      end
      max_impact = raw_impacts.max.to_f

      recs.each_with_index.map do |r, i|
        matches = Array(r.catalog_matches)
        impact_score = max_impact.positive? ? (raw_impacts[i] / max_impact).round(3) : nil
        {
          "id" => r.id,
          "title" => r.title,
          "description" => r.description,
          "implementation_outline" => r.implementation_outline,
          "catalog_matches" => matches,
          "priority" => r.priority,
          "related_signal_ids" => Array(r.related_signal_ids),
          "related_pattern_ids" => Array(r.related_pattern_ids),
          "impact_score" => impact_score,
          "feasibility_score" => feasibility_score(r, matches, stack_names)
        }
      end
    end

    # Coarse floor so priority still orders recs that lack linked-signal evidence.
    def priority_floor(priority)
      case priority.to_s.downcase
      when "high" then 1.0
      when "low" then 0.2
      else 0.5
      end
    end

    # Feasibility from real signals: extending an owned system is easier than a
    # greenfield build; a concrete implementation outline raises confidence.
    def feasibility_score(rec, matches, stack_names)
      score = matches.any? ? 0.6 : 0.5
      extends_stack = matches.any? do |m|
        next false unless m.is_a?(Hash)

        name = (m["name"] || m["vendor"]).to_s.downcase
        name.present? && stack_names.any? { |s| s.include?(name) || name.include?(s) }
      end
      score += 0.25 if extends_stack
      score += 0.05 if rec.implementation_outline.to_s.strip.present?
      score.clamp(0.15, 0.95).round(3)
    end

    def situation_json(docs_first)
      top_patterns = @company.patterns.order(confidence: :desc).limit(3)
      top_signals = @company.company_signals.order(strength: :desc).limit(3)
      doc_count = @company.documents.where(status: "ready").count
      depts = @company.documents.where(status: "ready").where.not(department: [nil, ""]).distinct.pluck(:department).compact

      context = if docs_first
                  "Worktruth reviewed #{doc_count} internal #{'document'.pluralize(doc_count)}" \
                    "#{depts.any? ? " spanning #{depts.join(', ')}" : ""} to establish an operations baseline" \
                    " before live interviews expand the evidence set."
                else
                  participation = Intelligence::SnapshotBuilder.call(company: @company)["participation"] || {}
                  completed = participation["completed"].to_i
                  invited = [participation["invited"].to_i, completed].max
                  "Worktruth analyzed discovery interviews (#{completed} of #{invited} completed)" \
                    "#{doc_count.positive? ? " alongside #{doc_count} internal documents" : ""} " \
                    "to surface where work slows, breaks, or depends on manual workarounds."
                end

      {
        "headline" => docs_first ? "Document baseline: where friction shows up today" : "Discovery findings: where work is hardest",
        "context" => context,
        "focus_areas" => top_patterns.map(&:title).presence || top_signals.map(&:label),
        "ask" => "The pages that follow show what we found, what it implies for the operating model, and where to act first."
      }
    end

    def implications_json
      signals_by_id = @company.company_signals.index_by(&:id)
      @company.patterns.order(confidence: :desc).limit(6).map do |pattern|
        linked = Array(pattern.linked_signal_ids).filter_map { |id| signals_by_id[id.to_i] }
        depts = Array(pattern.departments).presence || linked.flat_map { |s| Array(s.departments) }.uniq
        evidence = linked.sum { |s| s.evidence_count.to_i }
        evidence = [evidence, linked.size].max
        dept_phrase = depts.any? ? depts.join(", ") : "multiple teams"
        {
          "pattern_id" => pattern.id,
          "title" => pattern.title,
          "departments" => depts,
          "signal_labels" => linked.map(&:label),
          "evidence_count" => evidence,
          "confidence" => pattern.confidence,
          "statement" =>
            "Left unaddressed, #{pattern.title} continues to compound across #{dept_phrase}" \
            "#{evidence.positive? ? ", with #{evidence} supporting evidence items already on record" : ""}."
        }
      end
    end

    def executive_summary(docs_first)
      docs_first ? docs_executive_summary : interview_executive_summary
    end

    def docs_executive_summary
      ready_docs = @company.documents.where(status: "ready")
      count = ready_docs.count
      depts = ready_docs.where.not(department: [nil, ""]).distinct.pluck(:department).compact
      profile_lead = profile_framing_sentence
      parts = [
        profile_lead,
        "Baseline discovery from #{count} internal #{'document'.pluralize(count)}" \
        "#{depts.any? ? " across #{depts.join(', ')}" : ""}."
      ].compact

      top_patterns = @company.patterns.order(confidence: :desc).limit(2).pluck(:title)
      top_signals = @company.company_signals.order(strength: :desc).limit(3).pluck(:label)
      if top_patterns.any?
        parts << "The strongest cross-cutting themes are #{top_patterns.join(' and ')}."
      elsif top_signals.any?
        parts << "Document analysis highlights #{top_signals.join(', ')}."
      end

      if top_signals.any? && top_patterns.any?
        parts << "Underlying friction shows up as #{top_signals.first(2).join(' and ')}."
      end

      pattern_count = @company.patterns.count
      if pattern_count.positive?
        parts << "#{pattern_count} cross-cutting #{'pattern'.pluralize(pattern_count)} inform the recommendations below."
      end

      parts << "Employee interviews can be added later to strengthen this baseline with live evidence."
      parts << goals_framing_sentence
      parts << departments_framing_sentence
      parts.compact.join(" ")
    end

    def interview_executive_summary
      participation = Intelligence::SnapshotBuilder.call(company: @company)["participation"] || {}
      invited = participation["invited"].to_i
      completed = participation["completed"].to_i
      parts = [profile_framing_sentence].compact
      parts << if completed.zero? && invited.zero?
                 "Discovery interviews have not started yet."
               elsif completed.zero? && invited.positive?
                 "#{invited} employees have been invited; interviews are in progress and will strengthen this baseline."
               else
                 "#{completed} of #{[invited, completed].max} employees completed discovery interviews."
               end

      doc_count = @company.documents.where(status: "ready").count
      parts << "Findings are reinforced by #{doc_count} internal #{'document'.pluralize(doc_count)}." if doc_count.positive?

      top_signals = @company.company_signals.order(strength: :desc).limit(3).pluck(:label)
      parts << "Top friction areas include #{top_signals.join(', ')}." if top_signals.any?

      pattern_count = @company.patterns.count
      parts << "#{pattern_count} cross-team #{'pattern'.pluralize(pattern_count)} inform the recommendations below." if pattern_count.positive?

      parts << goals_framing_sentence
      parts << departments_framing_sentence
      parts.compact.join(" ")
    end

    def profile_framing_sentence
      profile = @company.company_profile
      industry = clean_industry(profile["industry"])
      size = profile["size_band"].presence
      region = profile["region"].presence || profile["country"].presence
      website = clean_website(@company.try(:website_url))
      return nil if industry.blank? && size.blank? && region.blank? && website.blank?

      subject = if industry
                  "This #{industry} organization"
                else
                  "This organization"
                end
      details = []
      details << "about #{size} people" if size
      details << "operating in #{region}" if region
      details << "website #{website}" if website
      details.any? ? "#{subject} (#{details.join(', ')}) is the focus of this report." : "#{subject} is the focus of this report."
    end

    # Non-informative industry catch-alls should not print as "This other
    # organization"; treat them as absent.
    def clean_industry(value)
      v = value.to_s.strip
      return nil if v.blank? || %w[other unknown n/a na none general].include?(v.downcase)

      v
    end

    # Placeholder/example domains must never reach a client deliverable.
    def clean_website(value)
      v = value.to_s.strip
      return nil if v.blank? || v.match?(/\A(https?:\/\/)?(www\.)?(example\.(com|org|net)|test\.|localhost|placeholder)/i)

      v
    end

    def goals_framing_sentence
      goals = @company.company_profile["business_goals"]
      goal_text = if goals.is_a?(Array)
                    goals.map(&:to_s).reject(&:blank?).first(4).join("; ")
                  else
                    goals.to_s.strip
                  end
      return nil if goal_text.blank?

      "Stated priorities include #{goal_text}."
    end

    def departments_framing_sentence
      depts = Array(@company.company_profile["org_departments"]).map(&:to_s).reject(&:blank?).first(8)
      return nil if depts.empty?

      "Departments in scope: #{depts.join(', ')}."
    end

    def normalize_excerpts(raw)
      Array(raw).filter_map do |item|
        if item.is_a?(Hash)
          text = (item["excerpt"] || item["text"] || item["body"] || item[:excerpt] || item[:text]).to_s.strip
          next if text.blank?

          { "excerpt" => text.truncate(280), "source" => item["source"] || item[:source] }
        else
          text = item.to_s.strip
          next if text.blank?

          { "excerpt" => text.truncate(280) }
        end
      end
    end

    def client_stack_json
      return [] unless defined?(CompanySystem) && CompanySystem.table_exists?

      @company.company_systems.active.order(:name).limit(20).map do |sys|
        {
          "id" => sys.id,
          "name" => sys.name,
          "category" => sys.category,
          "source" => sys.source,
          "confidence" => sys.confidence
        }
      end
    end

    def agentic_ideas_json
      return [] unless defined?(AgenticIdea) && AgenticIdea.table_exists?

      @company.agentic_ideas.published.includes(:solution_catalog_entry).order(confidence: :desc).limit(12).map do |idea|
        {
          "id" => idea.id,
          "title" => idea.title,
          "summary" => idea.summary,
          "system_fit" => idea.system_fit,
          "value_time" => idea.value_time,
          "value_efficiency" => idea.value_efficiency,
          "value_cost" => idea.value_cost,
          "approx_timeline" => idea.approx_timeline,
          "estimated_cost" => idea.estimated_cost,
          "confidence" => idea.confidence,
          "catalog_name" => idea.solution_catalog_entry&.name
        }
      end
    end

    def supporting_media_json
      MediaAttachment.where(company_id: @company.id, status: "ready")
                     .includes(:employee)
                     .order(created_at: :desc)
                     .limit(20)
                     .map do |attachment|
        insights = attachment.structured_insights.presence || {}
        {
          "id" => attachment.id,
          "attachment_type" => attachment.attachment_type,
          "caption" => attachment.caption,
          "summary" => insights["summary"].presence || attachment.extracted_text.to_s.truncate(200),
          "conversation_id" => attachment.conversation_id,
          "employee_department" => attachment.employee.department,
          "confidence" => attachment.confidence
        }
      end
    end

    def supporting_documents_json
      @company.documents.ready.order(created_at: :desc).limit(12).map do |doc|
        {
          "id" => doc.id,
          "filename" => doc.filename,
          "department" => doc.department,
          "document_type" => doc.try(:document_type),
          "sensitivity" => doc.try(:sensitivity),
          "source" => doc.source,
          "summary" => doc.insights_preview.is_a?(Hash) ? doc.insights_preview["summary"] : nil,
          "chunk_count" => doc.insights_preview.is_a?(Hash) ? doc.insights_preview["chunk_count"] : nil
        }
      end
    end

    def knowledge_base_json
      @company.company_knowledge_entries.active.order(updated_at: :desc).limit(40).map do |e|
        {
          "id" => e.id,
          "entry_type" => e.entry_type,
          "title" => e.title,
          "content" => e.content.to_s.truncate(500),
          "confidence" => e.confidence,
          "department" => e.department,
          "source_document_ids" => e.source_document_ids,
          "source" => e.metadata["source"],
          "url" => e.metadata["url"]
        }.compact
      end
    end

    def tools_catalog_json
      curated = []

      if defined?(CompanyCatalogMatch) && CompanyCatalogMatch.table_exists?
        curated = CompanyCatalogMatch
          .where(company_id: @company.id)
          .includes(:solution_catalog_entry)
          .order(score: :desc)
          .limit(12)
          .map do |match|
            entry = match.solution_catalog_entry
            {
              "solution_id" => entry.id,
              "name" => entry.name,
              "vendor" => entry.vendor,
              "category" => entry.category,
              "url" => entry.website_url,
              "partnership_tier" => entry.partnership_tier,
              "first_party" => entry.try(:first_party) == true,
              "reviewer_added" => match.added_by_reviewer_id.present?,
              "reviewer_name" => match.try(:added_by_reviewer)&.name,
              "reason" => match.why_it_fits,
              "score" => match.score,
              "matched_at" => match.matched_at,
              "already_in_stack" => Array(match.evidence_used).any? { |e| e.is_a?(Hash) && e["already_in_stack"] == true },
              "placement" => Array(match.evidence_used).any? { |e| e.is_a?(Hash) && e["already_in_stack"] == true } ? "extends_stack" : "new_capability"
            }
          end
      end

      if curated.empty?
        matches = @company.recommendations.published.flat_map { |r| Array(r.catalog_matches) }
        curated = matches.filter_map do |m|
          next unless m.is_a?(Hash)

          {
            "solution_id" => m["solution_id"] || m[:solution_id],
            "name" => m["name"] || m[:name],
            "vendor" => m["vendor"] || m[:vendor],
            "category" => m["category"] || m[:category],
            "url" => m["url"] || m[:url],
            "partnership_tier" => m["partnership_tier"] || m[:partnership_tier],
            "reason" => m["reason"] || m[:reason],
            "score" => m["score"] || m[:score]
          }
        end.uniq { |m| m["solution_id"] || m["name"] }
      end

      endorsements = []
      if defined?(CatalogEndorsement) && CatalogEndorsement.table_exists?
        endorsements = CatalogEndorsement
          .where(company_id: @company.id, publishable: true)
          .includes(:solution_catalog_entry, :reviewer_user)
          .order(created_at: :desc)
          .limit(20)
          .map do |e|
            entry = e.solution_catalog_entry
            {
              "disposition" => e.disposition,
              "rationale" => e.rationale,
              "source_url" => e.source_url,
              "solution_catalog_entry_id" => e.solution_catalog_entry_id,
              "solution_name" => entry&.name,
              "solution_vendor" => entry&.vendor,
              "reviewer_user_id" => e.reviewer_user_id,
              "reviewer_name" => e.reviewer_user&.name,
              "created_at" => e.created_at&.iso8601
            }
          end
      end

      curated = curated.map do |tool|
        related = endorsements.select { |e| e["solution_catalog_entry_id"].to_i == tool["solution_id"].to_i }
        tool.merge("endorsements" => related)
      end

      {
        "curated_matches" => curated.first(8),
        "endorsements" => endorsements,
        "disclaimer" => "Catalog suggestions are advisory. Reviewer-validated picks appear with endorsement notes below."
      }
    end
  end
end
