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
set :linked_dirs, %w{
  bin
  log
  tmp/pids
  tmp/cache
  tmp/sockets
  vendor/bundle
  public/system
  public/plugin_assets
}

# Default value for default_env is {}
# set :default_env, { path: "/opt/ruby/bin:$PATH" }

# Default value for keep_releases is 5
# set :keep_releases, 5
set :keep_releases, 20

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

desc "Backup database"
task :backup do
  on roles(:app) do
    execute "/etc/cron.daily/backup-db-redmine_production"
    download! "backups/redmine_production.sql", "redmine_production.sql"
  end
end

namespace :restore do
  namespace :check do
    desc "Check local sql file"
    task :file do
      on roles(:app) do
        local_path = "redmine_production.sql"
        if !Pathname(local_path).exist?
          error "`#{local_path}' is not found."
          exit 1
        end
      end
    end

    desc "Check remote database"
    task :no_relations do
      on roles(:app) do
        within release_path do
          with rails_env: fetch(:rails_env), lc_all: "C" do
            remote_path = release_path + "tmp" + "d"
            upload!(StringIO.new("\\d\n"), remote_path)
            begin
              s = capture :rails, "db production < #{remote_path}"
              if s != "No relations found."
                error "Remote database is not empty."
                exit 1
              end
            ensure
              execute :rm, remote_path.to_s
            end
          end
        end
      end
    end
  end

  task check: %w[check:file check:no_relations]
end

desc "Restore database"
task restore: 'restore:check' do
  local_path = Pathname("redmine_production.sql")
  on roles(:app) do
    within release_path do
      with rails_env: fetch(:rails_env) do
        remote_path = release_path + "tmp" + local_path.basename
        upload!(local_path.to_s, remote_path.to_s)
        execute :rails, "db production < #{remote_path}"
        execute :rm, remote_path.to_s
      end
    end
  end
end

desc "Drop database"
task :drop do
  set :need_run, ask("Do you want database to drop? Type `yes' or other", "")
  set :really_need_run, ask("Really? Type `yes' or other", "")
  on roles(:app) do
    within release_path do
      with rails_env: fetch(:rails_env) do
        info "CAUTION CAUTION CAUTION CAUTION CAUTION CAUTION CAUTION CAUTION"
        if (key = fetch(:need_run)) != "yes" ||
            (key = fetch(:really_need_run)) != "yes"
          info "You typed #{key.inspect}. Now canceling."
          exit
        end
        execute :rake, "db:drop"
      end
    end
  end
end
