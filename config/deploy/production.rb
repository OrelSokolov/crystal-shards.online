# The production server. SSH access as `deploy` user required.
server ENV.fetch("DEPLOY_HOST", "crystal-shards.online"), user: "deploy", roles: %w[app]
set :branch, ENV.fetch("BRANCH", "master")
