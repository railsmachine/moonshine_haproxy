require File.join(File.dirname(__FILE__), 'spec_helper.rb')

describe "A manifest with the HAProxy plugin" do

  before do
    @manifest = HaproxyManifest.new
    @manifest.haproxy
  end

  it "should be executable" do
    @manifest.should be_executable
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

    it "should support a default_backed plus a global default_backend" do
      @manifest.haproxy(:default_backend => 'app1', :frontends => [{ :name => 'mail', :default_backend => 'mail1' }])
      @manifest.files['/etc/haproxy/haproxy.cfg'].content.should match /default_backend mail1/
      @manifest.files['/etc/haproxy/haproxy.cfg'].content.should match /default_backend app1/
    end

    it "should have option options" do
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