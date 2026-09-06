# frozen_string_literal: true

module Api
  module V1
    module Consultant
      class BaseController < ApplicationController
        include ConsultantAuthenticatable
      end
    end
  end
end
