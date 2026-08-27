# frozen_string_literal: true

module Api
  module V1
    # Serializes the consultant handover. Read-only for now — the amend and
    # follow-up actions arrive with the consultant review work.
    module DiscoveryPackageJson
      extend ActiveSupport::Concern

      private

      # Preload for a set of conversations so the workspace, which lists every
      # conversation for a company, doesn't issue a query per employee.
      def discovery_packages_by_conversation(conversation_ids)
        DiscoveryPackage
          .current
          .where(conversation_id: conversation_ids)
          .includes(:discovery_package_items, :discovery_followup_questions)
          .order(version: :desc)
          .index_by(&:conversation_id)
      end

      def discovery_package_json(package)
        return nil unless package

        {
          id: package.id,
          version: package.version,
          status: package.status,
          recommendation: package.recommendation,
          recommendation_rationale: package.recommendation_rationale,
          confidence: package.confidence,
          # Surfaced deliberately: a consultant should know when a package was
          # assembled without a model, because it carries no solutions and a
          # deliberately low confidence.
          generated_by: package.generated_by,
          built_without_model: package.built_without_model?,
          generated_at: package.generated_at,
          error_message: package.error_message,
          issues: package.discovery_package_items.select { |i| i.kind == "issue" }
                         .sort_by { |i| [i.ordinal, i.id] }.map { |i| package_item_json(i) },
          solutions: package.discovery_package_items.select { |i| i.kind == "solution" }
                            .sort_by { |i| [i.ordinal, i.id] }.map { |i| package_item_json(i) },
          followup_questions: package.discovery_followup_questions
                                     .sort_by { |q| [q.queue_position, q.id] }
                                     .map { |q| followup_question_json(q) }
        }
      end

      def package_item_json(item)
        {
          id: item.id,
          kind: item.kind,
          title: item.title,
          body: item.body,
          impact: item.impact,
          origin: item.origin,
          status: item.status,
          linked_item_id: item.linked_item_id,
          ordinal: item.ordinal
        }
      end

      def followup_question_json(question)
        {
          id: question.id,
          body: question.body,
          rationale: question.rationale,
          status: question.status,
          queue_position: question.queue_position,
          # True when the interview parked this thread rather than drilling into it.
          from_parked_aside: question.from_parked_aside?,
          sent_at: question.sent_at,
          answered_at: question.answered_at
        }
      end
    end
  end
end
