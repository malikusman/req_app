# frozen_string_literal: true

class GenerateReportJob < ApplicationJob
  queue_as :default

  def perform(report_id)
    report = Report.find_by(id: report_id)
    return unless report

    Reports::GenerateReportService.call(report: report)
  end
end
