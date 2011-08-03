require File.join(File.dirname(__FILE__), 'spec_helper.rb')

describe "A manifest with the HAProxy plugin" do

  before do
    @manifest = HaproxyManifest.new
    @manifest.haproxy
  end

  it "should be executable" do
    @manifest.should be_executable
  end

  it "should install a default version" do
    @manifest.execs['download haproxy'].command.should match /wget http:\/\/haproxy.1wt.eu\/download\/1.4\/src\/haproxy-1.4.15.tar.gz/
  end

  it "should install a custom version" do
    @manifest.haproxy(:version => '2.3.11')
    @manifest.execs['download haproxy'].command.should match /wget http:\/\/haproxy.1wt.eu\/download\/2.3\/src\/haproxy-2.3.11.tar.gz/
  end

  it "should not install Apache by default" do
    pending
  end

  it "should install Apache if SSL is needed" do
    pending
  end

  describe "frontends" do

    it "should have a default" do
      @manifest.files['/etc/haproxy/haproxy.cfg'].content.should match /frontend rails/
    end

    it "should support custom frontends and ignore the default frontends" do
      @manifest.haproxy(:frontends => [{ :name => 'mail' }])
      @manifest.files['/etc/haproxy/haproxy.cfg'].content.should match /frontend mail/
      @manifest.files['/etc/haproxy/haproxy.cfg'].content.should_not match /frontend rails/
    end

    it "should support a default_backend" do
      @manifest.haproxy(:frontends => [{ :name => 'mail', :default_backend => 'mail1' }])
      @manifest.files['/etc/haproxy/haproxy.cfg'].content.should match /default_backend mail1/
    end

    it "should have extra options" do
      @manifest.haproxy(:frontends => [{ :name => 'rails', :options => ['frontend option1', 'frontend option2'] }])
      @manifest.files['/etc/haproxy/haproxy.cfg'].content.should match /^\s*frontend option1$/
      @manifest.files['/etc/haproxy/haproxy.cfg'].content.should match /^\s*frontend option2$/
    end

  end

  #it "should provide packages/services/files" do
  # @manifest.packages.keys.should include 'foo'
  # @manifest.files['/etc/foo.conf'].content.should match /foo=true/
  # @manifest.execs['newaliases'].refreshonly.should be_true
  #end

end