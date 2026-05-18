# frozen_string_literal: true

module Api
  module V1
    module Reviewer
      class BaseController < ApplicationController
        include ReviewerAuthenticatable
      end
    end
  end
end
