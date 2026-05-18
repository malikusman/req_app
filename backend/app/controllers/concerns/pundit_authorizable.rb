# frozen_string_literal: true

module PunditAuthorizable
  extend ActiveSupport::Concern

  class_methods do
    def pundit_context(&block)
      include Pundit::Authorization
      define_method(:pundit_user, &block)
    end
  end
end
