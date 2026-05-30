# frozen_string_literal: true

module AccessCodes
  class RotateAllService
    def self.call(company:, rotated_by: nil)
      new(company: company, rotated_by: rotated_by).call
    end

    def initialize(company:, rotated_by: nil)
      @company = company
      @rotated_by = rotated_by
    end

    def call
      @company.rotate_join_code!
    end
  end
end
