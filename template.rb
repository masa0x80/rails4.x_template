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

run "bundle exec rails g rspec:install"
append_file ".rspec", "--format documentation"
git add: "."
git commit: "-m '[command] bundle exec rails g rspec:install'"

after_bundle do
  git add: "."
  git commit: "-m '[command] bundle exec spring binstab --all'"

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
end
