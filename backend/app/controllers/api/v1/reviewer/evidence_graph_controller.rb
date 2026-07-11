# frozen_string_literal: true

module Api
  module V1
    module Reviewer
      class EvidenceGraphController < BaseController
        def show
          company = policy_scope(::Company).find(params[:company_id])
          authorize company, :show?
          graph = Evidence::GraphBuilder.call(company: company)
          render json: { graph: graph, evidence_graph: graph }
        end
      end
    end
  end
end
