# frozen_string_literal: true

module Api
  module V1
    module Platform
      class BaseController < ApplicationController
        include PlatformAuthenticatable
      end
    end
  end
end
