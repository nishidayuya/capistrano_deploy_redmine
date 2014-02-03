# config valid only for Capistrano 3.1
lock '3.1.0'

set :application, "redmine"
set :scm, :git
set :repo_url, "https://github.com/redmine/redmine.git"

# Default branch is :master
# ask :branch, proc { `git rev-parse --abbrev-ref HEAD`.chomp }
set :branch, "2.4.2"

# Default deploy_to directory is /var/www/my_app
# set :deploy_to, '/var/www/my_app'
set :deploy_to, "/opt/#{fetch(:application)}"

# Default value for :scm is :git
# set :scm, :git

# Default value for :format is :pretty
# set :format, :pretty

# Default value for :log_level is :debug
# set :log_level, :debug
set :log_level, :debug

# Default value for :pty is false
# set :pty, true

# Default value for :linked_files is []
# set :linked_files, %w{config/database.yml}
set :linked_files, %w{config/database.yml config/configuration.yml}

# Default value for linked_dirs is []
# set :linked_dirs, %w{bin log tmp/pids tmp/cache tmp/sockets vendor/bundle public/system}
set :linked_dirs, %w{bin log tmp/pids tmp/cache tmp/sockets vendor/bundle public/system}

# Default value for default_env is {}
# set :default_env, { path: "/opt/ruby/bin:$PATH" }

# Default value for keep_releases is 5
# set :keep_releases, 5

set :rbenv_type, :system
set :rbenv_ruby, "2.0.0-p353"
set :rails_env, "production"
set :assets_roles, []

files_path = Pathname("files")

namespace :deploy do
  namespace :check do
    desc "Check local files"
    task :local_files do
      on roles(:all) do
        invalid_paths = []
        files_path.find do |path|
          next if path.extname != ".example"
          not_example_basename = path.basename.to_s.sub(/\.example\z/, "")
          created_file_path = path.parent + not_example_basename
          next if created_file_path.exist?
          invalid_paths << created_file_path
        end
        if invalid_paths.length > 0
          error "not found configuration files: #{invalid_paths.map(&:to_s).inspect}"
          exit 1
        end
      end
    end
  end
  before :check, "check:local_files"

  desc "Upload files"
  task :upload do
    on roles(:app) do
      base_path = files_path + "app"
      base_path.find do |local_path|
        next if !local_path.file? || /~\z/.match(local_path.to_s)
        remote_path = Pathname("/") + local_path.relative_path_from(base_path)
        execute :mkdir, "-p", remote_path.parent
        upload!(local_path.to_s, remote_path)
      end
    end
  end
  before :check, :upload

  desc "Restart application"
  task :restart do
    on roles(:app), in: :sequence, wait: 5 do
      execute :mkdir, "-p", release_path.join("tmp")
      execute :touch, release_path.join("tmp/restart.txt")
    end
  end
  after :publishing, :restart
end
