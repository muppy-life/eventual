import Config

# Configure the test database
config :eventual, Eventual.Repo,
  database: "eventual_test",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 5442,
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# Print only warnings and errors during test
config :logger, level: :warning
