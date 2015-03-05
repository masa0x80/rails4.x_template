@database = options["database"]

# git init
git :init
git add: "."
git commit: "-m '[command] rails new #{app_name} -d #{@database}'"

run "mv config/database.yml config/database.yml.tmpl"

# .gitignore
run "cat <<-EGI >> .gitignore

*.swp
config/database.yml
config/application.yml
vendor/bundle
EGI"

git add: "-A"
git commit: "-m 'config/database.ymlをgitの管理外に'"

run "cp config/database.yml.tmpl config/database.yml"

# Gemfile
append_file "Gemfile", <<-EGF

# See https://github.com/sstephenson/execjs#readme for more supported runtimes
gem 'therubyracer', platforms: :ruby

# Use Unicorn as the app server
gem 'unicorn'

# Use Capistrano for deployment
gem 'capistrano-rails',    group: :development
gem "capistrano-rbenv",    group: :development
gem "capistrano-bundler",  group: :development
gem "capistrano3-unicorn", group: :development

# settingslogic
gem "settingslogic"

# slim-rails
gem "slim-rails"

# pry
gem "pry-rails",  group: [:development, :test]
gem "pry-byebug", group: [:development, :test]

# rspec
gem "rspec-rails", group: [:development, :test]

# factory_girl
gem "factory_girl_rails"

# annotate
gem "annotate", group: :development
EGF

file "app/models/settings.rb", <<-'EOC'
class Settings < Settingslogic
  source "#{Rails.root}/config/application.yml"
  namespace Rails.env
end
EOC

file "config/application.yml.tmpl", <<-'EOC'
defaults: &defaults

development:
  <<: *defaults
test:
  <<: *defaults
production:
  <<: *defaults
EOC

run "cp config/database.yml config/database.yml.tmpl"
run "cp config/application.yml.tmpl config/application.yml"

run "bundle install --path=vendor/bundle --jobs=4"
run "bundle package"
git add: "."
git commit: "-m '[command] bundle instal --path=vendor/bundle; bundle package'"

after_bundle do
  run "bundle exec cap install"
  git add: "."
  git commit: "-m '[command] bundle exec cap install'"

  gsub_file "Capfile", "# require 'capistrano/rbenv'", "require 'capistrano/rbenv'"
  gsub_file "Capfile", "# require 'capistrano/bundler'", "require 'capistrano/bundler'"
  inject_into_file "config/deploy.rb", after: "# set :keep_releases, 5\n" do
    <<-CODE.strip_heredoc
      
      # skip capistrano stats
      Rake::Task['metrics:collect'].clear_actions
    CODE
  end
  gsub_file "config/deploy.rb", "# set :keep_releases, 5", "set :keep_releases, 5"
  git add: "."
  git commit: "-m 'updaet capistrano settings'"

  run "bundle exec rails g rspec:install"
  append_file ".rspec", "--format documentation"
  git add: "."
  git commit: "-m '[command] bundle exec rails g rspec:install'"

  rakefile("auto_annotate.rake") do
    <<-TASK.strip_heredoc
      task :annotate do
        puts "Annotating models..."
        system "bundle exec annotate"
      end

      if Rails.env == "development"
        Rake::Task["db:migrate"].enhance do
          Rake::Task["annotate"].invoke
        end

        Rake::Task["db:rollback"].enhance do
          Rake::Task["annotate"].invoke
        end
      end
    TASK
  end
  git add: "."
  git commit: "-m 'settings for annotate automatically'"

  if yes?("use devise?")
    append_file "Gemfile", <<-EOG.strip_heredoc
      
      # devise
      gem "devise"
    EOG

    run "bundle install"
    git add: "."
    git commit: "-m '[gem] devise'"

    if yes?("generate with basic option?")
      generate "devise:install"
      git add: "."
      git commit: "-m '[command] bundle exec rails g devise:install'"

      generate "devise", "user"
      git add: "."
      git commit: "-m '[command] bundle exec rails g devise user'"

      rake "db:create"
      rake "db:migrate"
      git add: "."
      git commit: "-m '[command] bundle exec rake db:migrate'"

      inject_into_file "app/controllers/application_controller.rb", after: "protect_from_forgery with: :exception\n" do
        "  before_action :authenticate_user!\n"
      end
      environment "config.action_mailer.default_url_options = { host: 'localhost', port: 3000 }", env: :development
      route "root to: 'top#index'"
      file "app/controllers/top_controller.rb", <<-CODE.strip_heredoc
        class TopController < ApplicationController
          def index
          end
        end
      CODE
      file "app/views/top/index.html.slim", <<-CODE.strip_heredoc
        h1 Top Page
      CODE

      git add: "."
      git commit: "-m 'generate for devise with basic parameters'"
    end
  end

  if yes?("use omniauth?")
    append_file "Gemfile", <<-EOG.strip_heredoc
      
      # omniauth
      gem "omniauth-oauth2"
    EOG

    run "bundle install"
    git add: "."
    git commit: "-m '[gem] omniauth-oauth2'"
  end

  if yes?("use bootstrap?")
    append_file "Gemfile", <<-EOG.strip_heredoc
      
      # bootstrap
      gem "bootstrap-sass"
      gem "bootstrap-sass-extras"
      gem "momentjs-rails"
      gem "bootstrap3-datetimepicker-rails"
    EOG
    run "bundle install"

    git add: "."
    git commit: "-m '[gem] bootstrap-sass, bootstrap-sass-extras, bootstrap-datetimepicker'"

    generate "bootstrap:install"
    git add: "."
    git commit: "-m '[command] bundle exec rails g bootstrap:install'"

    generate "bootstrap:layout", "application", "fluid"
    git add: "."
    git commit: "-m '[command] bundle exec rails g bootstrap:layout application fluid'"

    run "rm app/views/layouts/application.html.erb"
    run "mv app/assets/stylesheets/application.css app/assets/stylesheets/application.scss"
    append_file "app/assets/stylesheets/application.scss", <<-CODE.strip_heredoc
      @import "bootstrap-sprockets";
      @import "bootstrap";
      @import "bootstrap-datetimepicker";

      body {
        padding: 65px;
      }
    CODE

    inject_into_file "app/assets/javascripts/application.js", after: "//= require jquery_ujs\n" do
      <<-CODE.strip_heredoc
        //= require bootstrap-sprockets
        //= require moment
        //= require bootstrap-datetimepicker
      CODE
    end
    git add: "-A"
    git commit: "-m 'add settings for bootstrap'"
  end

  if yes?("use kaminari?")
    append_file "Gemfile", <<-EGF.strip_heredoc
      
      # kaminari
      gem "kaminari"
    EGF

    run "bundle install"
    git add: "."
    git commit: "-m '[gem] kaminari'"

    generate "kaminari:config"
    git add: "."
    git commit: "-m '[command] bundle exec rails g kaminari:config'"

    kaminari_theme = ask("which theme of kaminari? [none|bootstrap3|foundation|github|google|purecss|semantic_ui]")
    unless kaminari_theme == "none"
      generate "kaminari:view", kaminari_theme
      git add: "."
      git commit: "-m '[command] bundle exec rails g kaminari:view #{kaminari_theme}'"
    end
  end
end
