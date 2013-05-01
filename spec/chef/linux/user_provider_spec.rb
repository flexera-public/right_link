# Copyright (c) 2013 RightScale Inc
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

require File.expand_path(File.join(File.dirname(__FILE__), '..', 'spec_helper'))

unless RightScale::Platform.windows?

require 'chef'
require 'etc'
require 'eventmachine'
require 'fileutils'
require 'right_popen'

require ::File.normalize_path(::File.join(::File.dirname(__FILE__), '..', 'chef_runner'))

class UserProviderSpec
  CURRENT_USER_NAME   = `whoami`.chomp
  CURRENT_UID         = ::Etc.getpwnam(CURRENT_USER_NAME).uid
  OWNER_ONLY_UMASK    = 0177
  OTHER_ONLY_UMASK    = 0573
  TEST_TEMP_PATH      = ::File.normalize_path(::File.join(::Dir.tmpdir, 'user-provider-spec-444f5d6698a4ab719a3169c166bc05ce'))
  TEST_COOKBOOKS_PATH = ::RightScale::Test::ChefRunner.get_cookbooks_path(TEST_TEMP_PATH)
  TEST_USER_NAME      = 'u8f10a67'
  TEST_USER_PASSWORD  = 32.times.map { rand(16).to_s(16) }.join
  TEST_GROUP_NAME     = 'g8f10a67'
  TEST_OUTPUT_FILE    = TEST_TEMP_PATH + '.txt'

  def self.sudo?
    CURRENT_USER_NAME == 'root'
  end
end

describe Chef::Provider::User do

  def run_as_recipe(user, group=nil, umask=nil)
    group_specifier = group ? "group #{group.inspect}" : ''
    umask_specifier = umask ? "umask \'0#{umask.to_s(8)}\'" : ''
    code = <<EOF
whoami >#{::UserProviderSpec::TEST_OUTPUT_FILE.inspect} 2>&1
groups >>#{::UserProviderSpec::TEST_OUTPUT_FILE.inspect} 2>&1
EOF

<<EOF
bash 'test script' do
  user #{user.inspect}
  #{group_specifier}
  #{umask_specifier}
  code #{code.inspect}
end
EOF
  end

  def create_cookbook
    ::RightScale::Test::ChefRunner.create_cookbook(
      ::UserProviderSpec::TEST_TEMP_PATH,
      {
        :create_user_recipe => (
<<EOF
user #{::UserProviderSpec::TEST_USER_NAME.inspect} do
  username #{::UserProviderSpec::TEST_USER_NAME.inspect}
  password #{::UserProviderSpec::TEST_USER_PASSWORD.inspect}
  home "/home/#{::UserProviderSpec::TEST_USER_NAME}"
  comment 'user_provider_spec test user'
  not_if { ::Etc.getpwnam(#{::UserProviderSpec::TEST_USER_NAME.inspect}) rescue nil }
end
EOF
        ),
        :create_group_recipe => (
<<EOF
group #{::UserProviderSpec::TEST_GROUP_NAME.inspect} do
  group_name #{::UserProviderSpec::TEST_GROUP_NAME.inspect}
  members [#{::UserProviderSpec::TEST_USER_NAME.inspect}]
  not_if { ::Etc.getgrnam(#{::UserProviderSpec::TEST_GROUP_NAME.inspect}) rescue nil }
end
EOF
        ),
        :remove_user_recipe => (
<<EOF
user #{::UserProviderSpec::TEST_USER_NAME.inspect} do
  username #{::UserProviderSpec::TEST_USER_NAME.inspect}
  action :remove
end
EOF
        ),
        :remove_group_recipe => (
<<EOF
group #{::UserProviderSpec::TEST_GROUP_NAME.inspect} do
  group_name #{::UserProviderSpec::TEST_GROUP_NAME.inspect}
  action :remove
end
EOF
        ),
        :run_script_as_current_user_recipe => run_as_recipe(
          ::UserProviderSpec::CURRENT_USER_NAME,
          nil,
          ::UserProviderSpec::OWNER_ONLY_UMASK),
        :run_script_as_current_uid_recipe => run_as_recipe(
          ::UserProviderSpec::CURRENT_UID,
          nil,
          ::UserProviderSpec::OWNER_ONLY_UMASK),
        :run_script_as_new_user_group_recipe => run_as_recipe(
          ::UserProviderSpec::TEST_USER_NAME,
          ::UserProviderSpec::TEST_GROUP_NAME,
          ::UserProviderSpec::OTHER_ONLY_UMASK)
      }
    )
  end

  def cleanup
    if ::File.directory?(UserProviderSpec::TEST_TEMP_PATH)
      ::FileUtils.rm_rf(::UserProviderSpec::TEST_TEMP_PATH) rescue nil
    end
  end

  # prints the sudo command line for so developers can perform a quick
  # integration test on their own system. the CI box is not expected to
  # run these tests as sudo but there should be QA coverage for running
  # a script recipe as another user.
  def print_sudo_command_line
    puts
    puts "NOTE: To run these tests without mocks as sudo execute the following manually:"
    puts
    puts "sudo #{`which bundle`.chomp} exec #{`which ruby`.chomp} #{`which spec`.chomp} #{::File.expand_path(__FILE__)}"
    puts
    true
  end

  def run_chef(*run_list)
    ::RightScale::Test::ChefRunner.run_chef(
      ::UserProviderSpec::TEST_COOKBOOKS_PATH,
      run_list.flatten)
  end

  let(:output_file) { ::UserProviderSpec::TEST_OUTPUT_FILE }

  before(:each) do
    ::File.unlink(output_file) if ::File.exists?(output_file)
  end

  after(:each) do
    ::File.unlink(output_file) rescue nil if ::File.exists?(output_file)
  end

  it_should_behave_like 'generates cookbook for chef runner'
  it_should_behave_like 'mocks logging'

  def assert_output_file_stat
    stat = ::File.stat(output_file)
    (stat.mode & 0777).to_s(8).should == (0777 - umask).to_s(8)
    if ::UserProviderSpec.sudo?
      stat.uid.should == ::Etc.getpwnam(user_name).uid
      stat.gid.should == ::Etc.getgrnam(group_name).gid if group_name
    end
    true
  end

  context 'given an existing user' do
    let(:group_name) { nil }
    let(:user_name)  { ::UserProviderSpec::CURRENT_USER_NAME }
    let(:umask)      { ::UserProviderSpec::OWNER_ONLY_UMASK }

    it 'should run script as current user' do
      # run script for current user name.
      run_chef('test::run_script_as_current_user_recipe')
      result = ::File.read(output_file).strip.split("\n")
      result[0].should == user_name
      result[1].split(' ').should include(user_name)
      assert_output_file_stat

      # run script for current uid.
      ::File.unlink(output_file)
      run_chef('test::run_script_as_current_uid_recipe')
      result = ::File.read(output_file).strip.split("\n")
      result[0].should == user_name
      result[1].split(' ').should include(user_name)
      assert_output_file_stat
    end
  end

  context 'given a new user/group' do
    let(:group_name) { ::UserProviderSpec::TEST_GROUP_NAME }
    let(:user_name)  { ::UserProviderSpec::TEST_USER_NAME }
    let(:umask)      { ::UserProviderSpec::OTHER_ONLY_UMASK }

    def mock_run_with_status(options, exit_code)
      ::EM.next_tick do
        pid = -1
        process = flexmock('process', :pid => pid)
        status = flexmock('status',
                          :success?   => exit_code == 0,
                          :exitstatus => exit_code)
        target = options[:target]
        target.method(options[:watch_handler]).call(process)
        target.method(options[:exit_handler]).call(status)
      end
      true
    end

    def instrument_user_group_run
      uid = nil
      gid = nil

      # chown the script to be run in the name of our user
      flexmock(::FileUtils).should_receive(:chown).once.and_return(true)

      # user struct
      flexmock(::Etc).should_receive(:getpwnam).with(user_name).and_return do
        if uid
          flexmock('user struct',
                   :uid    => uid,
                   :gid    => uid,
                   :gecos  => "#{user_name},,,", # General Electric Comprehensive Operating Supervisor ;)
                   :dir    => "/home/#{user_name}",
                   :shell  => "/bin/bash",
                   :passwd => "x")
        else
          raise ::ArgumentError, "Yo no sé quién es #{user_name}"
        end
      end

      # group struct
      flexmock(::Etc).should_receive(:getgrnam).with(group_name).and_return do
        if gid
          flexmock('group struct', :gid => gid, :mem => [user_name])
        else
          raise ::ArgumentError, "No se puede pertenecer a #{group_name}"
        end
      end

      # We will control the horizontal. We will control the vertical.
      # We will rightly popen all (now that everything goes through exactly one
      # gem API call to fork ;)
      flexmock(::RightScale::RightPopen).
        should_receive(:popen3_async).
        times(6).
        and_return do |cmd, options|
          cmd = cmd.join(' ') if cmd.kind_of?(::Array)
          cmd = cmd.gsub(/^sh \-c /, '').gsub(/\'|\"/, '').split(' ')
          case cmd[0]
          when 'gpasswd'
            succeeded =
              cmd.include?(::UserProviderSpec::TEST_GROUP_NAME) &&
              cmd.include?(::UserProviderSpec::TEST_USER_NAME)
            mock_run_with_status(options, succeeded ? 0 : 100)
          when 'groupadd'
            gid = 1066
            mock_run_with_status(options, cmd.include?(group_name) ? 0 : 200)
          when 'groupdel'
            gid = nil
            mock_run_with_status(options, cmd.include?(group_name) ? 0 : 201)
          when 'useradd'
            uid = 1492
            mock_run_with_status(options, cmd.include?(user_name) ? 0 : 300)
          when 'userdel'
            uid = nil
            mock_run_with_status(options, cmd.include?(user_name) ? 0 : 301)
          when 'bash'
            old_umask = ::File.umask(options[:umask])
            exit_code = nil
            begin
              system(*cmd)
              exit_code = $?.exitstatus
            ensure
              ::File.umask(old_umask)
            end
            mock_run_with_status(options, exit_code)
          else
            raise "unexpected command: #{cmd.inspect}"
          end
          true
        end
    end

    it 'should create user/group and run script as user' do
      # run the integration test for reals if sudo, mock otherwise.
      unless ::UserProviderSpec.sudo?
        print_sudo_command_line if ENV['VERBOSE'] == 'true'
        instrument_user_group_run
      end

      # create user/group and run script.
      run_chef('test::create_user_recipe',
               'test::create_group_recipe',
               'test::run_script_as_new_user_group_recipe')
      ::Etc.getpwnam(user_name).uid.should_not == 0
      ::Etc.getgrnam(group_name).gid.should_not == 0

      if ::UserProviderSpec.sudo?
        # root is other (not owner) so we can read file (but also because we are
        # sudo ;)
        result = ::File.read(output_file).strip.split("\n")
        result[0].should == user_name
        result[1].split(' ').should include(group_name)
      else
        # non-sudo so file owner is current user and we expect access denied.
        expect { ::File.read(output_file) }.to raise_error(::Errno::EACCES)
      end
      assert_output_file_stat

      # remove user/group.
      run_chef('test::remove_user_recipe', 'test::remove_group_recipe')
      if ::UserProviderSpec.sudo?
        expect { ::Etc.getpwnam(user_name) }.to raise_error(::ArgumentError)
        expect { ::Etc.getgrnam(group_name) }.to raise_error(::ArgumentError)
      end
    end
  end

end

end # unless windows
