# .gitignore
run "cat <<-EGI >> .gitignore

*.swp
config/database.yml
config/application.yml
vendor/bundle
EGI"

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
gem "pry-rails"
gem "pry-byebug"

# rspec
gem "rspec-rails"
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
git :init
git add: "."
git commit: "-m 'rails new -m rails4.2/template.rb'"

run "bundle exec rails g rspec:install"
append_file ".rspec", "--format documentation"
git add: "."
git commit: "-m '[command] bundle exec rails g rspec:install'"

after_bundle do
  git add: "."
  git commit: "-m '[command] bundle exec spring binstab --all'"
end
