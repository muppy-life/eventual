import Config

# Configure the list of Ecto repositories
config :eventual, ecto_repos: [Eventual.Repo]

# Configure the Eventual repository
config :eventual, Eventual.Repo,
  database: "eventual_events",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 5432,
  pool_size: 10

# Import environment specific config (if it exists)
if File.exists?("config/#{config_env()}.exs") do
  import_config "#{config_env()}.exs"
end
