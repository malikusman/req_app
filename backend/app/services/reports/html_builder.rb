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
          #{executive_summary_section}

          <h2>Key findings</h2>
          #{key_findings_section}

          <h2>Top pain points</h2>
          #{signals_table}

          <h2>Cross-team patterns</h2>
          #{patterns_section}

          <h2>Recommendations</h2>
          #{recommendations_section}

          <p class="meta" style="margin-top: 3rem;">Confidential — prepared for authorized stakeholders. Employee responses are summarized; raw chat logs are not included.</p>
        </body>
        </html>
      HTML
    end

    private

    def executive_summary_section
      ai = @snapshot.dig("ai_narratives", "executive_summary")
      if ai.present?
        paragraphs = ai.split(/\n\n+/).map { |p| "<p>#{ERB::Util.html_escape(p)}</p>" }.join
        return paragraphs
      end

      <<~HTML
        <p>This report synthesizes WhatsApp discovery interviews and uploaded documents into operational pain points, cross-team patterns, and actionable recommendations.</p>
        <p>Participation: #{@snapshot.dig('participation', 'completed')} of #{@snapshot.dig('participation', 'invited')} employees completed interviews.</p>
      HTML
    end

    def key_findings_section
      findings = @snapshot.dig("ai_narratives", "key_findings") || []
      return "<p><em>See pain points and patterns below.</em></p>" if findings.empty?

      "<ul>#{findings.map { |f| "<li>#{ERB::Util.html_escape(f)}</li>" }.join}</ul>"
    end

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
        "<tr><td>#{ERB::Util.html_escape(s['label'])}</td><td>#{pct}%</td><td>#{ERB::Util.html_escape((s['departments'] || []).join(', '))}</td></tr>"
      end.join

      "<table><thead><tr><th>Signal</th><th>Strength</th><th>Departments</th></tr></thead><tbody>#{rows}</tbody></table>"
    end

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
