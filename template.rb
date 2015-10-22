APPLICATION_CSS  = 'app/assets/stylesheets/application.css'.freeze
APPLICATION_SCSS = 'app/assets/stylesheets/application.scss'.freeze

@app_name = app_name
@database = options['database']

@flag = Hash.new(false)
@flag[:use_devise] = yes?('Use devise? [y|n]')
if @flag[:use_devise]
  @flag[:initialize_devise] = yes?("\tInitialize devise? [y|n]")
  @flag[:use_omniauth]      = yes?("\tUse omniauth? [y|n]")
end
@flag[:use_bootstrap] = yes?('Use bootstrap? [y|n]')
@flag[:use_kaminari]  = yes?('Use kaminari? [y|n]')
if @flag[:use_kaminari]
  @kaminari_theme = ask("\tWhich kaminari theme? [none|bootstrap3|google|purecss|semantic_ui]")
end
@flag[:use_compass] = yes?('Use compass? [y|n]')
if @flag[:use_compass]
  @flag[:use_compass_reset] = yes?("\tUse 'compass/reset'? [y|n]")
end
@flag[:use_knife] = yes?('Setup infra using knife-solo? [y|n]')
if @flag[:use_knife]
  @flag[:separate_infra_repo] = yes?("\tSeparate infra repository from #{@app_name}? [y|n]")
end

git :init

# Fix ruby version
run 'rbenv local $(rbenv version | cut -d " " -f 1)'
git add: '.ruby-version'
git commit: "-m 'Fix ruby version'"

# direnv settings
run 'echo \'export PATH=$PWD/bin:$PWD/vendor/bin:$PATH\' > .envrc && direnv allow'

# rails new
run 'rm -rf test'
git add: '.'
git commit: "-m '[command] rails new #{@app_name} -T -d #{@database}'"

run 'mv config/database.yml config/database.yml.tmpl'

# .gitignore
append_file '.gitignore', <<-EOF.strip_heredoc

  .DS_Store
  *.swp

  /.envrc

  /config/database.yml
  /config/application.yml

  /vendor/bundle
  /vendor/bin
EOF
if @flag[:separate_infra_repo]
  append_file '.gitignore', <<-EOF.strip_heredoc

    /infra
  EOF
end

git add: '.'
git commit: "-m 'config/{application,database}.ymlをgit管理外に変更'"

# Gemfile
gsub_file       'Gemfile', /gem 'mysql2'/, "gem 'mysql2', ' ~> 0.3.0'" if @database == 'mysql'
comment_lines   'Gemfile', /gem 'coffee-rails'/
uncomment_lines 'Gemfile', /gem 'unicorn'/
append_file 'Gemfile', <<-EOF.strip_heredoc

  gem 'settingslogic'

  gem 'slim-rails'

  group :development, :test do
    # pry
    gem 'pry-rails'
    gem 'pry-doc'
    gem 'pry-byebug'

    gem 'rspec-rails'
    gem 'spring-commands-rspec'

    gem 'factory_girl_rails'
  end

  group :development do
    # Use Capistrano for deployment
    gem 'capistrano-rails',    require: false
    gem 'capistrano-rbenv',    require: false
    gem 'capistrano-bundler',  require: false
    gem 'capistrano3-unicorn', require: false

    gem 'annotate'

    gem 'bullet'
  end
EOF
git add: '.'
git commit: "-m '各種gemの追加'"

file 'app/models/settings.rb', <<-'EOF'
class Settings < Settingslogic
  source "#{Rails.root}/config/application.yml"
  namespace Rails.env
end
EOF

file 'config/application.yml.tmpl', <<-EOF
defaults: &defaults

development:
  <<: *defaults
test:
  <<: *defaults
production:
  <<: *defaults
EOF

run 'cp config/application.yml.tmpl config/application.yml'
git add: '.'
git commit: "-m 'Initialize settingslogic'"

if @database == 'mysql'
  inject_into_file 'config/database.yml.tmpl', after: "  encoding: utf8\n" do
    "  charset: utf8\n  collation: utf8_general_ci\n"
  end
  git add: '.'
  git commit: "-m 'DBのcollation設定をutf8_general_ciに変更'"
end
run 'cp config/database.yml.tmpl config/database.yml'

Bundler.with_clean_env do
  run 'bundle install --path=vendor/bundle --binstubs=vendor/bin --jobs=4; bundle package'
end
git add: '.'
git commit: '-m \'[command] bundle install --path=vendor/bundle --binstubs=vendor/bin; bundle package\''

Bundler.with_clean_env do
  run 'bundle exec cap install'
end
git add: '.'
git commit: "-m '[command] cap install'"

uncomment_lines 'Capfile', /require 'capistrano\/rbenv/
uncomment_lines 'Capfile', /require 'capistrano\/bundler/
inject_into_file 'config/deploy.rb', after: "# set :keep_releases, 5\n" do
  <<-CODE.strip_heredoc

    # skip capistrano stats
    Rake::Task['metrics:collect'].clear_actions
  CODE
end
uncomment_lines 'config/deploy.rb', /set :keep_releases, 5/
git add: '.'
git commit: "-m 'Update capistrano settings'"

Bundler.with_clean_env do
  generate 'rspec:install'
end
git add: '.'
git commit: "-m '[command] rails g rspec:install'"

append_file '.rspec', '--format documentation'
inject_into_file 'spec/spec_helper.rb', after: "RSpec.configure do |config|\n" do
  "  config.include FactoryGirl::Syntax::Methods\n"
end
git add: '.'
git commit: "-m 'Initialize rspec'"

rakefile('auto_annotate.rake') do
  <<-CODE.strip_heredoc
    task :annotate do
      puts 'Annotating models...'
      system 'bundle exec annotate'
    end

    if Rails.env.to_sym == :development
      Rake::Task['db:migrate'].enhance do
        Rake::Task['annotate'].invoke
      end

      Rake::Task['db:rollback'].enhance do
        Rake::Task['annotate'].invoke
      end
    end
  CODE
end
git add: '.'
git commit: "-m 'Auto-annotate settings'"

Bundler.with_clean_env do
  run 'bundle exec spring binstub --all'
end
git add: '.'
git commit: "-m '[command] spring binstub --all'"

run 'mkdir -p script/setup'
file 'script/setup/git-hooks.sh', <<-'CODE'.strip_heredoc
  #!/bin/sh

  DIR_PATH=`dirname $0`
  cd $DIR_PATH; cd ../..;
  PROJECT_ROOT=`pwd`

  TARGET_PATH="${PROJECT_ROOT}/.git/hooks/prepare-commit-msg"
  cat <<-'EOF'> $TARGET_PATH
  #!/bin/sh

  if [ "$2" == '' ]; then
    mv $1 $1.tmp
    ISSUE_NUMBER=`git rev-parse --abbrev-ref @ | sed -e 's/^[^0-9]*\([0-9]*\).*/\1/'`
    if [ ! -z $ISSUE_NUMBER ]; then
      echo "[#${ISSUE_NUMBER}] " > $1
    fi
    cat $1.tmp >> $1
  fi
  EOF
  chmod +x $TARGET_PATH
CODE
git add: '.'
git commit: "-m 'Add git-hooks setup file'"
run 'sh script/setup/git-hooks.sh'

if @flag[:use_devise]
  append_file 'Gemfile', <<-EOF.strip_heredoc

    gem 'devise'
  EOF

  Bundler.with_clean_env do
    run 'bundle update'
  end
  git add: '.'
  git commit: "-m '[gem] devise'"

  if @flag[:initialize_devise]
    Bundler.with_clean_env do
      generate 'devise:install'
    end
    git add: '.'
    git commit: "-m '[command] rails g devise:install'"

    Bundler.with_clean_env do
      generate :devise, 'user'
    end
    git add: '.'
    git commit: "-m '[command] rails g devise user'"

    Bundler.with_clean_env do
      rake 'db:create'
      rake 'db:migrate'
    end
    git add: '.'
    git commit: "-m '[command] rake db:migrate'"

    inject_into_file 'app/controllers/application_controller.rb', after: "protect_from_forgery with: :exception\n" do
      "  before_action :authenticate_user!\n"
    end
    environment "config.action_mailer.default_url_options = { host: 'localhost', port: 3000 }", env: :development
    file 'app/controllers/top_controller.rb', <<-CODE.strip_heredoc
      class TopController < ApplicationController
        def index
        end
      end
    CODE
    file 'app/views/top/index.html.slim', <<-CODE.strip_heredoc
      h1 Top Page
    CODE
    route "root to: 'top#index'"

    git add: '.'
    git commit: "-m 'Initialize devise'"
  end

  if @flag[:use_omniauth]
    append_file 'Gemfile', <<-EOF.strip_heredoc

      gem 'omniauth-oauth2'
    EOF

    Bundler.with_clean_env do
      run 'bundle update'
    end
    git add: '.'
    git commit: "-m '[gem] omniauth-oauth2'"
  end
end

if @flag[:use_bootstrap]
  append_file 'Gemfile', <<-EOF.strip_heredoc

    # bootstrap
    gem 'bootstrap-sass'
    gem 'bootstrap-sass-extras'
    gem 'momentjs-rails'
    gem 'bootstrap3-datetimepicker-rails'
  EOF
  Bundler.with_clean_env do
    run 'bundle update'
  end
  git add: '.'
  git commit: "-m '[gem] bootstrap-sass, bootstrap-sass-extras, momentjs-rails, bootstrap-datetimepicker-rails'"

  Bundler.with_clean_env do
    generate 'bootstrap:install'
  end
  git add: '.'
  git commit: "-m '[command] rails g bootstrap:install'"

  Bundler.with_clean_env do
    generate 'bootstrap:layout', 'application', 'fluid'
  end
  git add: '.'
  git commit: "-m '[command] rails g bootstrap:layout application fluid'"

  run 'rm app/views/layouts/application.html.erb'
  run "mv #{APPLICATION_CSS} #{APPLICATION_SCSS}" if File.exist?(APPLICATION_CSS)
  append_file 'app/assets/stylesheets/application.scss', <<-CODE.strip_heredoc
    @import 'bootstrap-sprockets';
    @import 'bootstrap';
    @import 'bootstrap-datetimepicker';

    body {
      padding: 65px;
    }
  CODE

  inject_into_file 'app/assets/javascripts/application.js', after: "//= require jquery_ujs\n" do
    <<-CODE.strip_heredoc
      //= require bootstrap-sprockets
      //= require moment
      //= require bootstrap-datetimepicker
    CODE
  end
  git add: '.'
  git commit: "-m 'Add bootstrap settings'"
end

unless @flag[:initialize_devise]
  Bundler.with_clean_env do
    rake 'db:create'
    rake 'db:migrate'
  end
  git add: '.'
  git commit: "-m '[command] rake db:create; rake db:migrate'"

  file 'app/controllers/top_controller.rb', <<-CODE.strip_heredoc
    class TopController < ApplicationController
      def index
      end
    end
  CODE
  file 'app/views/top/index.html.slim', <<-CODE.strip_heredoc
    h1 Top Page
  CODE
  route "root to: 'top#index'"

  git add: '.'
  git commit: "-m 'Add top page'"
end

if @flag[:use_kaminari]
  append_file "Gemfile", <<-EOF.strip_heredoc

    gem 'kaminari'
  EOF

  Bundler.with_clean_env do
    run 'bundle update'
  end
  git add: '.'
  git commit: "-m '[gem] kaminari'"

  Bundler.with_clean_env do
    generate 'kaminari:config'
  end
  git add: '.'
  git commit: "-m '[command] rails g kaminari:config'"

  unless @kaminari_theme == 'none'
    Bundler.with_clean_env do
      generate 'kaminari:views', @kaminari_theme
    end
    git add: '.'
    git commit: "-m '[command] rails g kaminari:views #{@kaminari_theme}'"
  end
end

if @flag[:use_compass]
  append_file 'Gemfile', <<-EOF.strip_heredoc

    gem 'compass-rails', git: 'https://github.com/Compass/compass-rails.git', branch: 'master'
  EOF

  Bundler.with_clean_env do
    run 'bundle update'
  end
  git add: '.'
  git commit: "-m '[gem] compass-rails'"

  run "mv #{APPLICATION_CSS} #{APPLICATION_SCSS}" if File.exist?(APPLICATION_CSS)
  append_file APPLICATION_SCSS, "@import 'compass';"
  append_file APPLICATION_SCSS, "@import 'compass/reset';" if @flag[:use_compass_reset]

  git add: '.'
  git commit: "-m 'Initialize compass'"
end

if @flag[:use_knife]
  run 'mkdir infra'

  config = {with: 'cd infra && '}
  if @flag[:separate_infra_repo]
    run 'git init', config

    # Fix ruby version
    run 'rbenv local $(rbenv version | cut -d " " -f 1)', config
    run 'git add .ruby-version',                          config
    run "git commit -m 'Fix ruby version'",               config

    # direnv settings
    run 'echo \'export PATH=$PWD/bin:$PWD/vendor/bin:$PATH\' > .envrc && direnv allow', config

    # .gitignore
    file 'infra/.gitignore', <<-EOF.strip_heredoc
      .DS_Store
      *.swp

      /.envrc

      /vendor/bundle
      /vendor/bin
      /.chef/data_bag_key
    EOF

    run 'git add .',                                                          config
    run "git commit -m 'encrypted_data_bag_secretファイルをgit管理外に変更'", config

    Bundler.with_clean_env do
      run 'bundle init', config
    end
    append_file 'infra/Gemfile', <<-EOF.strip_heredoc

      gem 'knife-solo', '~> 0.4.0'
      gem 'knife-solo_data_bag'
      gem 'berkshelf'
    EOF
    Bundler.with_clean_env do
      run 'bundle install --path=vendor/bundle --binstubs=vendor/bin --jobs=4 --gemfile=Gemfile; bundle package', config
    end
    run 'git add .',                                                                                             config
    run 'git commit -m \'[command] bundle install --path=vendor/bundle --binstubs=vendor/bin; bundle package\'', config
  else
    # .gitignore
    file 'infra/.gitignore', <<-EOF.strip_heredoc
      /.chef/data_bag_key
    EOF

    git add: '.'
    git commit: "-m 'encrypted_data_bag_secretファイルをgit管理外に変更'"

    append_file 'Gemfile', <<-EOF.strip_heredoc

      group :development do
        gem 'knife-solo', '~> 0.4.0'
        gem 'knife-solo_data_bag'
        gem 'berkshelf'
      end
    EOF
    Bundler.with_clean_env do
      run 'bundle update'
    end
    git add: '.'
    git commit: "-m '[gem] knife-solo, knife-solo_data_bag, berkshelf'"
  end

  Bundler.with_clean_env do
    run 'bundle exec knife solo init .', config
  end
  run 'git add .',                                         config
  run 'git commit -m \'[command] knife solo init infra\'', config

  run 'openssl rand -base64 512 > .chef/data_bag_key', config
  gsub_file 'infra/.chef/knife.rb', /#encrypted_data_bag_secret "data_bag_key"/, 'encrypted_data_bag_secret ".chef/data_bag_key"'
  run 'git add .',                                          config
  run 'git commit -m "Add encrypted_data_bag_secret file"', config

  if @flag[:separate_infra_repo]
    run 'mkdir -p script/setup', config
    file 'infra/script/setup/git-hooks.sh', <<-'CODE'.strip_heredoc
      #!/bin/sh

      DIR_PATH=`dirname $0`
      cd $DIR_PATH; cd ../..;
      PROJECT_ROOT=`pwd`

      TARGET_PATH="${PROJECT_ROOT}/.git/hooks/prepare-commit-msg"
      cat <<-'EOF'> $TARGET_PATH
      #!/bin/sh

      if [ "$2" == '' ]; then
        mv $1 $1.tmp
        ISSUE_NUMBER=`git rev-parse --abbrev-ref @ | sed -e 's/^[^0-9]*\([0-9]*\).*/\1/'`
        if [ ! -z $ISSUE_NUMBER ]; then
          echo "[#${ISSUE_NUMBER}] " > $1
        fi
        cat $1.tmp >> $1
      fi
      EOF
      chmod +x $TARGET_PATH
    CODE
    run 'git add .',                                config
    run 'git commit -m "Add git-hooks setup file"', config
    run 'sh script/setup/git-hooks.sh',             config
  end
end
