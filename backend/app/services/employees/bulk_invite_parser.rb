# frozen_string_literal: true

require "csv"
require "roo"
require "stringio"

module Employees
  class BulkInviteParser
    SUPPORTED_EXTENSIONS = %w[.csv .xlsx].freeze

    def self.call(file:)
      new(file: file).call
    end

    def initialize(file:)
      @file = file
      @filename = file.original_filename.to_s
    end

    def call
      extension = File.extname(@filename).downcase
      raise ArgumentError, "Only CSV and XLSX files are supported" unless SUPPORTED_EXTENSIONS.include?(extension)

      extension == ".csv" ? parse_csv : parse_xlsx
    end

    private

    def parse_csv
      csv = CSV.parse(@file.read, headers: true)
      csv.map { |row| normalize_row(row.to_h) }.reject { |r| r.values.all?(&:blank?) }
    end

    def parse_xlsx
      rows = []
      xlsx = Roo::Spreadsheet.open(StringIO.new(@file.read), extension: :xlsx)
      headers = xlsx.row(1).map { |h| h.to_s.strip.downcase }
      (2..xlsx.last_row).each do |idx|
        values = xlsx.row(idx)
        row_hash = headers.each_with_index.to_h { |h, i| [h, values[i]] }
        normalized = normalize_row(row_hash)
        rows << normalized unless normalized.values.all?(&:blank?)
      end
      rows
    end

    def normalize_row(row)
      {
        phone_e164: row["phone_e164"].to_s.strip.presence,
        email: row["email"].to_s.strip.presence,
        display_name: row["display_name"].to_s.strip.presence,
        department: row["department"].to_s.strip.presence
      }
    end
  end
end
