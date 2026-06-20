# frozen_string_literal: true

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    app_host = ENV.fetch("APP_HOST", "http://localhost:5173")
    origins app_host,
            app_host.sub("https://", "http://"),
            "http://localhost:5173",
            "http://127.0.0.1:5173"
    resource "*",
      headers: :any,
      methods: %i[get post put patch delete options head],
      expose: %w[Authorization],
      credentials: false
  end
end
