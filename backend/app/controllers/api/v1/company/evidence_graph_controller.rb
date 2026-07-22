# frozen_string_literal: true

module Api
  module V1
    module Company
      class EvidenceGraphController < BaseController
        def show
          authorize current_company, :show?
          graph = Evidence::GraphBuilder.call(company: current_company)
          render json: { graph: graph, evidence_graph: graph }
        end
      end
    end
  end
end
