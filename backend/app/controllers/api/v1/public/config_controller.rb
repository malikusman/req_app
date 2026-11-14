# frozen_string_literal: true

module Api
  module V1
    module Public
      # Switches the public site needs before anyone signs in.
      class ConfigController < ApplicationController
        def show
          render json: { company_signup_enabled: CompanyRegistrationsController.enabled? }
        end
      end
    end
  end
end
