# Backend testing

The API uses [RSpec](https://rspec.info/) with request specs (HTTP integration) and service specs (business logic).

## Setup

```bash
cd backend
bundle install
```

Ensure PostgreSQL is running and create the test database:

```bash
RAILS_ENV=test bundle exec rails db:prepare
```

With Docker Compose:

```bash
docker compose exec rails bash -c 'RAILS_ENV=test DATABASE_URL=postgres://req_app:req_app@postgres:5432/req_app_test bundle install && bundle exec rails db:test:prepare && bundle exec rspec'
```

## Run tests

```bash
bundle exec rspec
# or
./bin/rspec
```

Run a subset:

```bash
bundle exec rspec spec/requests
bundle exec rspec spec/services
```

## Layout

| Path | Purpose |
|------|---------|
| `spec/requests/` | API request specs (auth, company, platform, internal) |
| `spec/services/` | Service object unit specs |
| `spec/factories/` | FactoryBot test data |
| `spec/support/auth_helpers.rb` | JWT and internal token helpers for requests |
