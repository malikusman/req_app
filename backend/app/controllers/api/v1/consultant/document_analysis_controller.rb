# frozen_string_literal: true

module Api
  module V1
    module Consultant
      class DocumentAnalysisController < BaseController
        before_action :set_company

        def show
          authorize DocumentAnalysisRun, :index?
          unless current_consultant_user.consultant_assignments.active.exists?(company_id: @company.id)
            return render json: { error: "forbidden" }, status: :forbidden
          end

          run = @company.document_analysis_runs.recent.first
          entries = @company.company_knowledge_entries.active.order(updated_at: :desc).limit(200)
          questions = @company.company_clarification_questions.for_consultant.order(created_at: :desc).limit(100)

          render json: {
            company_id: @company.id,
            latest_run: run && run_json(run),
            events: run ? run.document_analysis_events.order(:created_at).map { |e| event_json(e) } : [],
            knowledge_entries: entries.map { |e| entry_json(e) },
            clarification_questions: questions.map { |q| question_json(q) }
          }
        end

        def dismiss_question
          question = @company.company_clarification_questions.find(params[:id])
          authorize question, :dismiss?
          question.update!(
            status: "dismissed_by_consultant",
            dismissed_by_consultant_user: current_consultant_user,
            dismissed_at: Time.current
          )
          render json: { clarification_question: question_json(question) }
        end

        private

        def set_company
          @company = ::Company.find(params[:company_id])
        end

        def run_json(run)
          {
            id: run.id,
            run_kind: run.run_kind,
            status: run.status,
            phase: run.phase,
            summary: run.summary,
            counters: run.counters,
            started_at: run.started_at,
            finished_at: run.finished_at,
            created_at: run.created_at
          }
        end

        def event_json(event)
          {
            id: event.id,
            agent_name: event.agent_name,
            event_type: event.event_type,
            phase: event.phase,
            message: event.message,
            payload: event.payload,
            created_at: event.created_at
          }
        end

        def entry_json(entry)
          {
            id: entry.id,
            entry_type: entry.entry_type,
            title: entry.title,
            content: entry.content,
            confidence: entry.confidence,
            department: entry.department,
            status: entry.status,
            source_document_ids: entry.source_document_ids,
            created_at: entry.created_at
          }
        end

        def question_json(q)
          {
            id: q.id,
            body: q.body,
            status: q.status,
            answer: q.answer,
            answer_source: q.answer_source,
            citations: q.citations,
            answered_at: q.answered_at,
            dismissed_at: q.dismissed_at,
            created_at: q.created_at
          }
        end
      end
    end
  end
end
