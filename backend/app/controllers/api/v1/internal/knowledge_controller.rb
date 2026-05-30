# frozen_string_literal: true

module Api
  module V1
    module Internal
      class KnowledgeController < ApplicationController
        include InternalAuthenticatable

        def search
          company = ::Company.find(params[:company_id])
          results = Knowledge::SemanticSearch.call(
            company: company,
            query: params[:query],
            limit: [params[:limit].to_i, 20].min.clamp(1, 20),
            source_types: params[:source_types]&.split(",")
          )
          render json: { results: results }
        end

        def profile
          company = ::Company.find(params[:company_id])
          render json: {
            company_id: company.id,
            profile_summary: Companies::ProfileSummary.for_display(company: company),
            profile_text: Companies::ProfileSummary.for_ai(company: company)
          }
        end

        def signals
          company = ::Company.find(params[:company_id])
          render json: {
            signals: company.company_signals.order(strength: :desc).limit(50).map { |s| signal_json(s) },
            patterns: company.patterns.order(confidence: :desc).limit(30).map { |p| pattern_json(p) }
          }
        end

        def employee_summaries
          company = ::Company.find(params[:company_id])
          employees = company.employees.order(updated_at: :desc).limit(100)
          employees = employees.where(department: params[:department]) if params[:department].present?

          render json: {
            employees: employees.map { |e| employee_summary_json(e) }
          }
        end

        def context_bundle
          company = ::Company.find(params[:company_id])
          bundle = Knowledge::ContextBundleService.call(
            company: company,
            department: params[:department]
          )
          render json: bundle
        end

        def conversation_excerpt
          conversation = ::Conversation.find(params[:conversation_id])
          messages = conversation.messages.order(:created_at).last(30)

          render json: {
            conversation_id: conversation.id,
            employee_id: conversation.employee_id,
            status: conversation.status,
            messages: messages.map { |m| { direction: m.direction, body: m.body, created_at: m.created_at } },
            insights: conversation.conversation_insights.order(:turn_number).map { |i|
              { turn_number: i.turn_number, summary: i.summary, structured_data: i.structured_data }
            }
          }
        end

        private

        def signal_json(signal)
          {
            id: signal.id,
            label: signal.label,
            signal_type: signal.signal_type,
            strength: signal.strength,
            departments: signal.departments
          }
        end

        def pattern_json(pattern)
          {
            id: pattern.id,
            title: pattern.title,
            description: pattern.description,
            confidence: pattern.confidence,
            status: pattern.status
          }
        end

        def employee_summary_json(employee)
          {
            id: employee.id,
            display_name: employee.display_name,
            department: employee.department,
            participation_status: employee.participation_status,
            agent_profile: employee.agent_profile,
            completed_at: employee.completed_at
          }
        end
      end
    end
  end
end
