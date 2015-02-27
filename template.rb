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
gem 'capistrano-rails', group: :development

# settingslogic
gem "settingslogic"
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
