#--  -*- mode: ruby; encoding: utf-8 -*-
# Copyright: Copyright (c) 2011 RightScale, Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# 'Software'), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#++

require 'right_agent/core_payload_types'

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'spec_helper'))
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'lib', 'instance', 'cook'))

module RightScale
  describe ReposeProxyDownloader do
    before(:each) do
      # reset env variables
      @old_env = {}
      ReposeProxyDownloader::PROXY_ENVIRONMENT_VARIABLES.each {|var|
        @old_env[var] = ENV[var]
        ENV.delete(var)
      }
    end
    after(:each) do
      @old_env.each {|key, value|
        if value.nil?
          ENV.delete(key)
        else
          ENV[key] = value
        end
      }
    end

    include RightScale::SpecHelper

    class TestException < Exception
      attr_accessor :reason
      def initialize(tuple)
        scope, resource, name, reason = tuple
        scope.should == "scope"
        resource.should == "resource"
        name.should == "name"
        @reason = reason
      end
    end

    before(:all) do
      setup_state
    end

    after(:all) do
      cleanup_state
    end

    context 'syntax' do
      it 'understands the full syntax with protocol' do
        ENV['HTTP_PROXY'] = "http://b/"

        ReposeProxyDownloader.new("scope", "resource", "ticket", "name",
                                  nil, nil).instance_variable_get(:@proxy).should ==
          URI.parse("http://b/")
      end

      it 'understands the abbreviated syntax without protocol' do
        ENV['HTTP_PROXY'] = "b:8080"

        ReposeProxyDownloader.new("scope", "resource", "ticket", "name",
                                  nil, nil).instance_variable_get(:@proxy).should ==
          URI.parse("http://b:8080/")
      end

      it 'understands the abbreviated syntax without protocol or port' do
        ENV['HTTP_PROXY'] = "b"

        ReposeProxyDownloader.new("scope", "resource", "ticket", "name",
                                  nil, nil).instance_variable_get(:@proxy).should ==
          URI.parse("http://b/")
      end
    end

    context 'environment variables' do
      it 'should read from HTTPS_PROXY first' do
        ENV['HTTPS_PROXY'] = "http://a/"
        ENV['HTTP_PROXY'] = "http://b/"
        ENV['http_proxy'] = "http://c/"
        ENV['ALL_PROXY'] = "http://d/"

        ReposeProxyDownloader.new("scope", "resource", "ticket", "name",
                                  nil, nil).instance_variable_get(:@proxy).should ==
          URI.parse("http://a/")
      end
      it 'should read from HTTP_PROXY if HTTPS_PROXY is not set' do
        ENV['HTTP_PROXY'] = "http://b/"
        ENV['ALL_PROXY'] = "http://c/"

        ReposeProxyDownloader.new("scope", "resource", "ticket", "name",
                                  nil, nil).instance_variable_get(:@proxy).should ==
          URI.parse("http://b/")
      end
      it 'should read from ALL_PROXY if nothing else is set' do
        ENV['ALL_PROXY'] = "http://c/"

        ReposeProxyDownloader.new("scope", "resource", "ticket", "name",
                                  nil, nil).instance_variable_get(:@proxy).should ==
          URI.parse("http://c/")
      end
    end

    context 'discovering hostnames' do
      it 'should not attempt IP lookup' do
        ReposeProxyDownloader.discover_repose_servers(["a-server", "b-server"])
        ips = ReposeProxyDownloader.class_eval { class_variable_get(:@@ips) }
        hostnames = ReposeProxyDownloader.class_eval { class_variable_get(:@@hostnames) }
        ips.should include("a-server")
        ips.should include("b-server")
        hostnames["a-server"].should == "a-server"
        hostnames["b-server"].should == "b-server"
      end
    end

    context 'making connections' do
      it 'should set up the HttpConnection properly with an ordinary proxy' do
        ENV['HTTPS_PROXY'] = 'http://a-proxy:2135/'
        proxy = ReposeProxyDownloader.new("scope", "resource", "ticket", "name", nil, nil)
        connection = proxy.send(:make_connection)
        connection.get_param(:proxy_host).should == "a-proxy"
        connection.get_param(:proxy_port).should == 2135
        connection.get_param(:proxy_username).should be_nil
        connection.get_param(:proxy_password).should be_nil
      end
      it 'should set up the HttpConnection properly with an proxy that needs authentication' do
        ENV['HTTPS_PROXY'] = 'http://username:password@a-proxy:2135/'
        proxy = ReposeProxyDownloader.new("scope", "resource", "ticket", "name", nil, nil)
        connection = proxy.send(:make_connection)
        connection.get_param(:proxy_host).should == "a-proxy"
        connection.get_param(:proxy_port).should == 2135
        connection.get_param(:proxy_username).should == "username"
        connection.get_param(:proxy_password).should == "password"
      end
    end

    context 'computing which class is used' do
      before(:each) do
        # reset env variables
        @old_env = {}
        ReposeProxyDownloader::PROXY_ENVIRONMENT_VARIABLES.each {|var|
          @old_env[var] = ENV[var]
          ENV.delete(var)
        }
      end
      after(:each) do
        @old_env.each {|key, value|
          if value.nil?
            ENV.delete(key)
          else
            ENV[key] = value
          end
        }
      end

      it 'should use ReposeProxyDownloader if HTTPS_PROXY is set' do
        ENV['HTTPS_PROXY'] = "foo"
        ReposeDownloader.select_repose_class.should == ReposeProxyDownloader
      end

      it 'should use ReposeProxyDownloader if HTTP_PROXY is set' do
        ENV['HTTP_PROXY'] = "foo"
        ReposeDownloader.select_repose_class.should == ReposeProxyDownloader
      end

      it 'should use ReposeProxyDownloader if http_proxy is set' do
        ENV['http_proxy'] = "foo"
        ReposeDownloader.select_repose_class.should == ReposeProxyDownloader
      end

      it 'should use ReposeProxyDownloader if ALL_PROXY is set' do
        ENV['ALL_PROXY'] = "foo"
        ReposeDownloader.select_repose_class.should == ReposeProxyDownloader
      end

      it 'should use ReposeDownloader otherwise' do
        ReposeDownloader.select_repose_class.should == ReposeDownloader
      end
    end
  end
end
