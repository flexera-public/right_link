# Copyright (c) 2009-2011 RightScale, Inc, All Rights Reserved Worldwide.
#
# THIS PROGRAM IS CONFIDENTIAL AND PROPRIETARY TO RIGHTSCALE
# AND CONSTITUTES A VALUABLE TRADE SECRET.  Any unauthorized use,
# reproduction, modification, or disclosure of this program is
# strictly prohibited.  Any use of this program by an authorized
# licensee is strictly subject to the terms and conditions,
# including confidentiality obligations, set forth in the applicable
# License Agreement between RightScale.com, Inc. and
# the licensee.

require File.expand_path(File.join(File.dirname(__FILE__), '..', 'spec_helper'))
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'scripts', 'server_importer'))

module RightScale
  describe ServerImporter do

    def run_server_importer(args)
      replace_argv(args)
      subject.run(subject.parse_args)
      return 0
    rescue SystemExit => e
      return e.status
    end

    before(:all) do
      # preserve old ARGV for posterity (although it's unlikely that anything
      # would consume it after startup).
      @old_argv = ARGV
    end

    after(:all) do
      # restore old ARGV
      replace_argv(@old_argv)
      @output = nil
    end

    before(:each) do
      @output = []
      flexmock(subject).should_receive(:puts).and_return { |message| @output << message; true }
      flexmock(subject).should_receive(:print).and_return { |message| @output << message; true }
    end

    context 'attach option' do
      let(:short_name)    {'-a'}
      let(:long_name)     {'--attach'}
      let(:key)           {:url}
      let(:value)         {'url'}
      let(:expected_value){value}
      it_should_behave_like 'command line argument'
    end

    context 'force option' do
      let(:short_name)    {'-f'}
      let(:long_name)     {'--force'}
      let(:key)           {:force}
      let(:value)         {['', '-a', 'url']}
      let(:expected_value){true}
      it_should_behave_like 'command line argument'
    end

    context 'cloud option' do
      let(:short_name)    {'-c'}
      let(:long_name)     {'--cloud'}
      let(:key)           {:cloud}
      let(:value)         {['cloud', '-a', 'url']}
      let(:expected_value){value[0]}
      it_should_behave_like 'command line argument'
    end

    context 'rs_connect --version' do
      it 'should reports RightLink version from gemspec' do
        run_server_importer('--version')
        @output.join('\n').should match /rs_connect \d+\.\d+\.?\d* - RightLink's server importer \(c\) 2011 RightScale/
      end
    end

    context 'rs_connect --help' do
      it 'should show usage info' do
        usage = Usage.scan(File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'scripts', 'server_importer.rb')))
        run_server_importer('--help')
        @output.join('\n').should include(usage) 
      end
    end

    def do_attach(url, force=false, cloud=nil)
        subject.should_receive(:fail).and_return { raise }
        subject.should_receive(:configure_logging)
        subject.should_receive(:http_get).with(url, false).and_return("RS_rn_id")
        flexmock(FileUtils).should_receive(:mkdir_p)
        file = flexmock('file')
        flexmock(File).should_receive(:open).and_return(file)
        file.should_receive(:puts)
        subject.should_receive(:`).with("/etc/init.d/rightscale start && /etc/init.d/rightlink start").once
        flexmock($?).should_receive(:success?).and_return(true)
        args = ['-a', url]
        args.push('-f') if force
        args.push('-c', cloud) if cloud
        run_server_importer(args)
    end

    context 'rs_connect -a url' do
      it 'should attach this machine to a server' do
        do_attach('url')
      end
    end

    context 'rs_connect -a url -f' do
      it 'should force attachment even if server appears already connected' do
        flexmock(File).should_receive(:exist?).with(InstanceState::STATE_FILE).and_return(true)
        do_attach('url', true)
      end
    end

    context 'rs_connect -a url -c cloud' do
      it 'should attach this machine to a server and set cloud name to "cloud"' do
        flexmock(RightScale::AgentConfig).should_receive(:cloud_file_path).and_return("cloud_file_path")
        flexmock(File).should_receive(:join)\
                      .with(RightScale::Platform.filesystem.spool_dir, "cloud", 'user-data.txt')\
                      .and_return("/var/spool/cloud/user-data.txt")
        do_attach('url', false, "cloud")
      end
    end

  end
end
