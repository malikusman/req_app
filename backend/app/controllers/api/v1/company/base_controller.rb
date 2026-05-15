# frozen_string_literal: true

module Api
  module V1
    module Company
      class BaseController < ApplicationController
        include CompanyAuthenticatable
      end
    end
  end
end
