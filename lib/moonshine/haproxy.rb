module Moonshine
  module Haproxy
    # Define options for this plugin via the <tt>configure</tt> method
    # in your application manifest:
    #
    #    configure(:haproxy => {:foo => true})
    #
    # Moonshine will autoload plugins, just call the recipe(s) you need in your
    # manifests:
    #
    #    recipe :haproxy
    def haproxy(options = {})
      # define the recipe
      # options specified with the configure method will be
      # automatically available here in the options hash.
      #    options[:foo]   # => true

      options = HashWithIndifferentAccess.new({
        :ssl     => false,
        :version => '1.4.15',
        :restart_on_change => false,
        :reload_on_change => true
      }.merge(options))
      
      options[:major_version] = options[:version].split('.')[0..1].join('.')

      if options[:major_version] == options[:version]
        options[:major_version] = options[:version].split("-").first
      end

      supports_ssl = false
      haproxy_vhost = :present
      
      if configuration[:haproxy][:use_ssl]
        supports_ssl = true
        haproxy_vhost = :absent
        if options[:major_version] == "1.4"
          raise "You must use at least version 1.5-dev22 of haproxy for SSL support."
        end
      end

      devel_url = ""

      if options[:version].include?("dev")
        devel_url = "/devel"
      end
      
      haproxy_download = "http://haproxy.1wt.eu/download/#{options[:major_version]}/src#{devel_url}/haproxy-#{options[:version]}.tar.gz"

      if options[:restart_on_change]
        haproxy_notifies = [service('haproxy')]
        haproxy_service_restart = "/etc/init.d/haproxy restart"
      elsif options[:reload_on_change] 
        haproxy_notifies = [service('haproxy')]
        haproxy_service_restart = "/etc/init.d/haproxy reload"
      else 
        haproxy_notifies = [] 
        haproxy_service_restart = "/etc/init.d/haproxy restart"
      end 
      
      target = "linux26"
      if ubuntu_precise?
        target = 'linux2628'
      end

      make_options = "TARGET=#{target} USE_PCRE=1 USE_STATIC_PCRE=1 USE_LINUX_SPLICE=1 USE_REGPARM=1"
      if supports_ssl
        make_options << " USE_OPENSSL=1 USE_ZLIB=1 clean all"
      end

      puts "Make Options for haproxy: #{make_options}"

      package 'socat', :ensure => :installed
      package 'haproxy', :ensure => :absent
      package 'wget', :ensure => :installed
      package 'libpcre3-dev', :ensure => :installed
      exec 'download haproxy',
        :command => "wget #{haproxy_download}",
        :require => package('wget'),
        :cwd     => '/usr/local/src',
        :creates => "/usr/local/src/haproxy-#{options[:version]}.tar.gz"
      exec 'untar haproxy',
        :command => "tar xzvf haproxy-#{options[:version]}.tar.gz",
        :require => exec('download haproxy'),
        :cwd     => '/usr/local/src',
        :creates => "/usr/local/src/haproxy-#{options[:version]}"
      exec 'compile haproxy',
        :command => 'make #{make_options}',
        :require => [exec('untar haproxy'), package('libpcre3-dev')],
        :cwd     => "/usr/local/src/haproxy-#{options[:version]}",
        :creates => "/usr/local/src/haproxy-#{options[:version]}/haproxy"
      package 'haproxy',
        :ensure   => :absent,
        :require   => exec('compile haproxy')
      exec 'install haproxy',
        :command => "sudo make install",
        :timeout => 0,
        :require => package('haproxy'),
        :cwd     => "/usr/local/src/haproxy-#{options[:version]}",
        :unless => "test -f /usr/local/sbin/haproxy && /usr/local/sbin/haproxy -v | grep 'version #{options[:version]} '"

      file '/etc/haproxy/', :ensure => :directory
      haproxy_cfg_template = options[:haproxy_cfg_template] || File.join(File.dirname(__FILE__), '..', '..', 'templates', 'haproxy.cfg.erb')
      
      errorfiles = {}
      error_code_descriptions = {
                                  '400' => "Bad Request",
                                  '403' => "Forbidden",
                                  '408' => "Request Timeout",
                                  '500' => "Internal Server Error",
                                  '503' => "Service Unavailable",
                                  '504' => "Gateway Timeout"
                                } 
      error_code_descriptions.each do |status,status_description|
        error_file = rails_root.join("public/#{status}.html")
        if error_file.exist?
          errorfiles[status] = "/etc/haproxy/#{status}.http"
          file "/etc/haproxy/#{status}.http",
            :ensure => :present,
            :before => file('/etc/haproxy/haproxy.cfg'),
            :notify => haproxy_notifies,
            :content => <<-END
HTTP/1.0 #{status} #{status_description}
Cache-Control: no-cache
Connection: close
Content-Type: text/html

#{error_file.read}          
END
        end
      end
      
      configure(:haproxy => {:errorfiles => errorfiles})

      disable_servers_lines = []
      enable_servers_lines = []
      options[:backends].each do |backend|
        backend[:servers].each do |server|
          unless server[:options].include? 'backup'
            disable_servers_lines << "disable server #{backend[:name]}/#{server[:name]}"
            enable_servers_lines << "enable server #{backend[:name]}/#{server[:name]}"
          end
        end
      end
      disable_servers_txt = "#{disable_servers_lines.join(";")}\n"
      enable_servers_txt = "#{enable_servers_lines.join(";")}\n"

      file '/etc/haproxy/haproxy.cfg',
        :ensure => :present,
        :notify => haproxy_notifies,
        :content => template(haproxy_cfg_template, binding)
      file '/etc/haproxy/disable_servers.txt',
        :ensure => :present,
        :content => disable_servers_txt
      file '/etc/haproxy/enable_servers.txt',
        :ensure => :present,
        :content => enable_servers_txt
      file '/etc/default/haproxy',
        :ensure => :present,
        :notify => service('haproxy'),
        :content => "ENABLED=1\n"

      file '/etc/init.d/haproxy',
        :ensure  => :present,
        :mode    => '755',
        :content => template(File.join(File.dirname(__FILE__), '..', '..', 'templates', 'init.d'), binding)
      service 'haproxy',
        :ensure => :running,
        :enable => true,
        :restart => haproxy_service_restart,
        :require => [package('haproxy'), exec('install haproxy'), file('/etc/init.d/haproxy')]

      service 'rsyslog',
        :ensure => :running

      file '/etc/rsyslog.d/99-haproxy.conf',
        :ensure => :absent,
        :notify => service('rsyslog')
      file '/etc/rsyslog.d/40-haproxy.conf',
        :ensure => :present,
        :notify => service('rsyslog'),
        :content => template(File.join(File.dirname(__FILE__), '..', '..', 'templates', 'haproxy.rsyslog.conf'))

      logrotate '/var/log/haproxy*.log',
        :options => ['daily', 'copytruncate', 'missingok', 'notifempty', 'compress', 'delaycompress', 'sharedscripts', 'rotate 7'],
        :postrotate => 'reload rsyslog >/dev/null 2>&1 || true'
      file "/etc/logrotate.d/varloghaproxy.conf", :ensure => :absent

      recipe :apache_server
      a2enmod 'headers'
      file "/etc/apache2/",
        :ensure => :directory,
        :mode => '755'

      file "/etc/apache2/apache2.conf",
        :alias => 'apache_conf',
        :ensure => :present,
        :content => template(File.join(File.dirname(__FILE__), '..', '..', 'templates', 'haproxy-apache2.conf'), binding),
        :mode => '644',
        :notify => service("apache2")

      file "/etc/apache2/ports.conf",
        :ensure => :present,
        :content => template(File.join(File.dirname(__FILE__), '..', '..', 'templates', 'haproxy-ports.conf'), binding),
        :mode => '644',
        :notify => service("apache2")

      a2dissite "000-default"

      file "/etc/apache2/sites-available/default",
        :alias => 'default_vhost',
        :ensure => :present,
        :content => template(File.join(File.dirname(__FILE__), '..', '..', 'templates', 'haproxy-default'), binding),
        :mode => '644',
        :notify => service("apache2")

      file "/etc/apache2/envvars",
        :alias => 'apache_envvars',
        :ensure => :present,
        :content => template(File.join(File.dirname(__FILE__), '..', '..', 'templates', 'haproxy-envvars'), binding),
        :mode => '644',
        :notify => service("apache2")

      file '/etc/apache2/sites-enabled/zzz_default', :ensure => '/etc/apache2/sites-available/default'

        file "/etc/apache2/sites-available/maintenance",
          :alias => 'maintenance_vhost',
          :ensure => :present,
          :content => template(File.join(File.dirname(__FILE__), '..', '..', 'templates', 'maintenance.vhost.erb'), binding),
          :notify => service("apache2")

        a2ensite "maintenance", :require => file('maintenance_vhost')

      ssl_configuration = configuration[:ssl] || options[:ssl] || {}
      if ssl_configuration.any?

        a2enmod 'proxy'
        a2enmod 'proxy_http'
        a2enmod 'proxy_connect'
        a2enmod 'ssl'


        file "/etc/apache2/ssl/",
          :ensure => :directory,
          :mode => '755'

        ssl_cert_files = [
          ssl_configuration[:certificate_file],
          ssl_configuration[:certificate_key_file],
          ssl_configuration[:certificate_chain_file]
        ].compact
        ssl_cert_files.each do |cert_file_path|
          file cert_file_path,
            :ensure => :present,
            :mode => '644',
            :notify => service("apache2")
        end

        file "/etc/apache2/sites-available/haproxy",
          :alias => 'haproxy_vhost',
          :ensure => haproxy_vhost,
          :content => template(File.join(File.dirname(__FILE__), '..', '..', 'templates', 'haproxy.vhost.erb'), binding),
          :notify => service("apache2"),
          :require => ssl_cert_files.map { |f| file(f) }

        unless configuration[:haproxy][:use_ssl]
          a2ensite "haproxy", :require => file('haproxy_vhost')
        end

      end
    end
    
  end
end
