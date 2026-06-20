# frozen_string_literal: true

module Reports
  class HtmlBuilder
    def self.call(snapshot:)
      new(snapshot: snapshot).call
    end

    def initialize(snapshot:)
      @snapshot = snapshot
    end

    def call
      company_name = @snapshot.dig("company", "name")
      delta = @snapshot["delta_from_previous"] || {}

      <<~HTML
        <!DOCTYPE html>
        <html lang="#{@snapshot.dig('company', 'locale') || 'en'}">
        <head>
          <meta charset="utf-8"/>
          <title>Workflow Discovery Report — #{ERB::Util.html_escape(company_name)}</title>
          <style>
            body { font-family: 'Helvetica Neue', Arial, sans-serif; color: #0f172a; margin: 40px; line-height: 1.5; }
            h1 { color: #0f172a; border-bottom: 3px solid #2563eb; padding-bottom: 8px; }
            h2 { color: #1e40af; margin-top: 2rem; }
            .meta { color: #64748b; font-size: 0.9rem; }
            .badge { display: inline-block; background: #dbeafe; color: #1e40af; padding: 2px 8px; border-radius: 4px; font-size: 0.85rem; }
            table { width: 100%; border-collapse: collapse; margin: 1rem 0; }
            th, td { text-align: left; padding: 8px 12px; border-bottom: 1px solid #e2e8f0; }
            th { background: #f8fafc; }
            .delta-box { background: #f0fdf4; border: 1px solid #86efac; padding: 1rem; border-radius: 8px; margin: 1rem 0; }
            .bar { height: 8px; background: #e2e8f0; border-radius: 4px; }
            .bar-fill { height: 100%; background: #3b82f6; border-radius: 4px; }
          </style>
        </head>
        <body>
          <h1>Workflow Discovery Report</h1>
          <p class="meta">#{ERB::Util.html_escape(company_name)} · Generated #{Time.current.strftime('%B %d, %Y')}</p>
          <p>Readiness score: <strong>#{@snapshot.dig('readiness', 'score')}%</strong></p>

          #{delta_section(delta)}

          <h2>Executive summary</h2>
          <p>This report synthesizes WhatsApp discovery interviews, optional voice notes, screenshots, documents, and uploaded files into operational pain points, cross-team patterns, and actionable recommendations.</p>
          <p>Participation: #{@snapshot.dig('participation', 'completed')} of #{@snapshot.dig('participation', 'invited')} employees completed interviews.</p>

          <h2>Top pain points</h2>
          #{signals_table}

          <h2>Cross-team patterns</h2>
          #{patterns_section}

          <h2>Recommendations</h2>
          #{recommendations_section}

          <h2>Supporting media</h2>
          #{supporting_media_section}

          <p class="meta" style="margin-top: 3rem;">Confidential — prepared for authorized stakeholders. Employee responses and media are summarized; raw chat logs and original attachments are not included.</p>
        </body>
        </html>
      HTML
    end

    private

    def delta_section(delta)
      return "" if delta["summary"].blank? || delta["summary"] == "Initial discovery report"

      <<~HTML
        <div class="delta-box">
          <strong>What's changed</strong>
          <p>#{ERB::Util.html_escape(delta['summary'])}</p>
        </div>
      HTML
    end

    def signals_table
      signals = @snapshot["signals"] || []
      return "<p><em>No signals detected yet.</em></p>" if signals.empty?

      rows = signals.map do |s|
        pct = (s["strength"].to_f * 100).round
        evidence = evidence_summary(s)
        "<tr><td>#{ERB::Util.html_escape(s['label'])}</td><td>#{pct}%</td><td>#{ERB::Util.html_escape((s['departments'] || []).join(', '))}</td><td>#{ERB::Util.html_escape(evidence)}</td></tr>"
      end.join

      "<table><thead><tr><th>Signal</th><th>Strength</th><th>Departments</th><th>Evidence</th></tr></thead><tbody>#{rows}</tbody></table>"
    end

    def evidence_summary(signal)
      count = signal["evidence_count"].to_i
      media = Array(signal["multimodal_evidence"])
      parts = ["#{count} mentions"]
      parts << "#{media.size} media item#{'s' unless media.size == 1}" if media.any?
      parts.join("; ")
    end

    def supporting_media_section
      media = @snapshot["supporting_media"] || []
      return "<p><em>No supporting media captured yet.</em></p>" if media.empty?

      rows = media.map do |item|
        summary = item["summary"].presence || item["caption"].presence || "Shared #{item['attachment_type']}"
        "<tr><td>#{ERB::Util.html_escape(item['attachment_type'].to_s)}</td><td>#{ERB::Util.html_escape(summary.to_s)}</td><td>#{ERB::Util.html_escape(item['employee_department'].to_s)}</td></tr>"
      end.join

      "<table><thead><tr><th>Type</th><th>Summary</th><th>Department</th></tr></thead><tbody>#{rows}</tbody></table>"

    def patterns_section
      patterns = @snapshot["patterns"] || []
      return "<p><em>No patterns detected yet.</em></p>" if patterns.empty?

      patterns.map do |p|
        "<h3>#{ERB::Util.html_escape(p['title'])}</h3><p>#{ERB::Util.html_escape(p['description'].to_s)}</p><p class='meta'>Confidence: #{(p['confidence'].to_f * 100).round}%</p>"
      end.join
    end

    def recommendations_section
      recs = @snapshot["recommendations"] || []
      return "<p><em>No recommendations yet.</em></p>" if recs.empty?

      recs.map do |r|
        tools = (r["catalog_matches"] || []).map { |c| c["name"] }.join(", ")
        tools_line = tools.present? ? "<p><em>Suggested tools: #{ERB::Util.html_escape(tools)}</em></p>" : ""
        "<h3>#{ERB::Util.html_escape(r['title'])}</h3><p>#{ERB::Util.html_escape(r['description'].to_s)}</p>#{tools_line}<p>#{ERB::Util.html_escape(r['implementation_outline'].to_s)}</p>"
      end.join
    end
  end
end
