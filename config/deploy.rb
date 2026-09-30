set :application, "crystal-shards"
set :repo_url, "git@github.com:OrelSokolov/crystal-shards.online.git"
set :branch, ENV.fetch("BRANCH", "master")
set :deploy_to, "/var/www/crystal-shards"
set :keep_releases, 5

# Persisted between releases: crawl data, logs, environment
append :linked_dirs, "data", "log"
append :linked_files, ".env.production"

set :crawler_bin, -> { release_path.join("bin/crawler") }

namespace :deploy do
  desc "Build release binaries with Crystal"
  task :build do
    on roles(:app) do
      within release_path do
        execute :crystal, "build --release -o bin/server src/server.cr"
        execute :crystal, "build --release -o bin/crawler src/crawler.cr"
      end
    end
  end
  before "deploy:published", :build

  desc "Restart crystal-shards service"
  task :restart do
    on roles(:app) do
      execute :sudo, :systemctl, :restart, "crystal-shards.service"
    end
  end
  after "deploy:published", :restart

  desc "Run the crawler once (useful right after the first deploy)"
  task :crawl do
    on roles(:app) do
      within current_path do
        execute "set -a; . ./.env.production; set +a; #{fetch(:crawler_bin)}"
      end
    end
  end
end
