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
        :ssl => true
      }.merge(options))

      package 'haproxy', :ensure => :installed
      file '/etc/haproxy/haproxy.cfg',
        :ensure => :present,
        :notify => service('haproxy'),
        :content => template(File.join(File.dirname(__FILE__), '..', '..', 'templates', 'haproxy.cfg.erb'))
      file '/etc/default/haproxy',
        :ensure => :present,
        :notify => service('haproxy'),
        :content => "ENABLED=1\n"
      service 'haproxy',
        :ensure => :running,
        :enable => true,
        :require => package('haproxy')
      
      if configuration[:ssl] && options[:ssl]            
        recipe :apache_server

        a2enmod 'proxy'
        a2enmod 'proxy_http'
        a2enmod 'proxy_connect'
        a2enmod 'headers'
        a2enmod 'ssl'

        file "/etc/apache2/",
          :ensure => :directory,
          :mode => '755'

        file "/etc/apache2/apache2.conf",
          :alias => 'apache_conf',
          :ensure => :present,
          :content => template(File.join(File.dirname(__FILE__), '..', '..', 'templates', 'haproxy-apache2.conf')),
          :mode => '644',
          :notify => service("apache2")

        file "/etc/apache2/ssl/",
          :ensure => :directory,
          :mode => '755'

        ssl_cert_files = [
          configuration[:ssl][:certificate_file],
          configuration[:ssl][:certificate_key_file],
          configuration[:ssl][:certificate_chain_file]
        ].compact
        ssl_cert_files.each do |cert_file_path|
          file cert_file_path,
            :ensure => :present,
            :mode => '644'
        end
          
        file "/etc/apache2/sites-available/haproxy",
          :alias => 'haproxy_vhost',
          :ensure => :present,
          :content => template(File.join(File.dirname(__FILE__), '..', '..', 'templates', 'haproxy.vhost.erb')),
          :notify => service("apache2"),
          :require => ssl_cert_files.map { |f| file(f) }
          
        file "/etc/apache2/ports.conf",
          :ensure => :present,
          :content => template(File.join(File.dirname(__FILE__), '..', '..', 'templates', 'haproxy-ports.conf')),
          :mode => '644',
          :notify => service("apache2")

        a2dissite "000-default"

        file "/etc/apache2/sites-available/default",
          :alias => 'default_vhost',
          :ensure => :present,
          :content => template(File.join(File.dirname(__FILE__), '..', '..', 'templates', 'haproxy-default')),
          :mode => '644',
          :notify => service("apache2")

        file "/etc/apache2/envvars",
          :alias => 'apache_envvars',
          :ensure => :present,
          :content => template(File.join(File.dirname(__FILE__), '..', '..', 'templates', 'haproxy-envvars')),
          :mode => '644',
          :notify => service("apache2")

        file '/etc/apache2/sites-enabled/zzz_default', :ensure => '/etc/apache2/sites-available/default'

        a2ensite "haproxy", :require => file('haproxy_vhost')
      end
    end
  end
end