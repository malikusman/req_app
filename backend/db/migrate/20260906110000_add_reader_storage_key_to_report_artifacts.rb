# frozen_string_literal: true

# The in-portal reader renders the report's HTML, not the PDF, so it can offer
# real section jump links instead of a scaled page image.
#
# It must show exactly what was approved. Re-rendering live from the snapshot
# would drift the moment a consultant touched a section override after approval,
# and could surface an un-approved edit to the client. So the HTML that produced
# the shipped PDF is stored beside it.
class AddReaderStorageKeyToReportArtifacts < ActiveRecord::Migration[7.1]
  def change
    add_column :report_artifacts, :reader_storage_key, :string
  end
end
