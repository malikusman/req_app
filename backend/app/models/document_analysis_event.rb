# frozen_string_literal: true

class DocumentAnalysisEvent < ApplicationRecord
  belongs_to :document_analysis_run

  validates :agent_name, :event_type, presence: true
end
