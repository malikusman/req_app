# frozen_string_literal: true

require "spec_helper"
ENV["RAILS_ENV"] = "test"
ENV["JWT_SECRET"] ||= "test-jwt-secret"
ENV["INTERNAL_API_TOKEN"] ||= "test-internal-token"
require_relative "../config/environment"
abort("The Rails environment is running in production mode!") if Rails.env.production?
require "rspec/rails"
require "webmock/rspec"

Dir[Rails.root.join("spec/support/**/*.rb")].sort.each { |f| require f }

WebMock.disable_net_connect!(allow_localhost: true)

RSpec.configure do |config|
  config.fixture_paths = [Rails.root.join("spec/fixtures")]
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  config.include FactoryBot::Syntax::Methods
  config.include AuthHelpers, type: :request
  config.include ActiveJob::TestHelper

  config.before do
    ActiveJob::Base.queue_adapter = :test
  end

  config.before(:each, type: :request) do
    host! "www.example.com"
  end
end
