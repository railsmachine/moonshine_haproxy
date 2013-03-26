# for capistrano/maintenance
set(:maintenance_dirname) do
  system_app_symlink = app_symlinks.detect {|symlink| symlink == 'system' }
  unless system_app_symlink
    raise "Missing 'system' in :app_symlinks. Please update `config/moonshine.yml`'s :app_symlinks to include 'system'"
  end

  "#{shared_path}/public/#{system_app_symlink}"
end
set :maintenance_config_warning, false

after 'deploy:web:disable', 'deploy:haproxy:disable'
before 'deploy:web:enable', 'deploy:haproxy:enable'

namespace :deploy do
  namespace :haproxy do
    task :disable, :roles => :web do
      sudo "socat unix-connect:/var/run/haproxy.stat  stdio < /etc/haproxy/disable_servers.txt"
    end

    task :enable, :roles => :web do
      sudo "socat unix-connect:/var/run/haproxy.stat  stdio < /etc/haproxy/enable_servers.txt"
    end
  end
end
