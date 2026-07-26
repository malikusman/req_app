# frozen_string_literal: true

module Api
  module V1
    module Company
      class ClarificationQuestionsController < BaseController
        def index
          authorize CompanyClarificationQuestion, :index?
          questions = policy_scope(CompanyClarificationQuestion).visible_to_admin.order(created_at: :desc).limit(100)
          render json: { clarification_questions: questions.map { |q| question_json(q) } }
        end

        def answer
          question = policy_scope(CompanyClarificationQuestion).find(params[:id])
          authorize question, :answer?
          answer = params[:answer].to_s.strip
          return render json: { error: "answer required" }, status: :unprocessable_entity if answer.blank?

          question.update!(
            status: "answered",
            answer: answer,
            answer_source: "admin",
            answered_by_company_user: current_company_user,
            answered_at: Time.current
          )
          render json: { clarification_question: question_json(question) }
        end

        private

        def question_json(q)
          {
            id: q.id,
            body: q.body,
            status: q.status,
            answer: q.answer,
            answer_source: q.answer_source,
            citations: q.citations,
            answered_at: q.answered_at,
            analysis_run_id: q.document_analysis_run_id,
            created_at: q.created_at,
            updated_at: q.updated_at
          }
        end
      end
    end
  end
end
