# Copyright (c) 2013 RightScale, Inc, All Rights Reserved Worldwide.
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
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'scripts', 'repose_get_manager'))

module RightScale
  describe RightLinkReposeGetManager do
    def run_repose_get_manager(args)
      replace_argv(args)
      subject.control(subject.parse_args)
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
      @error = nil
      @output = nil
    end

    before(:each) do
      @output = []
      flexmock(subject).should_receive(:puts).and_return { |message| @output << message; true }
      flexmock(STDOUT).should_receive(:puts).and_return { |message| @output << message; true }
    end

    context 'resource option' do
      let(:short_name)      {'-r'}
      let(:long_name)       {'--resource'}
      let(:key)             {:resource}
      let(:value)           {'uri'}
      let(:expected_value)  {'uri'}
      it_should_behave_like 'command line argument'
    end

    context 'out-file option' do
      let(:short_name)      {'-o'}
      let(:long_name)       {'--out-file'}
      let(:key)             {:out_file}
      let(:value)           {'file'}
      let(:expected_value)  {'file'}
      it_should_behave_like 'command line argument'
    end

    context 'repose_get --resource URI --out-file /path/to/out/file repose_server' do
      it 'should download URI to /path/out/file via repose' do
        repose = flexmock("repose")
        file = flexmock("file")
        flexmock(ReposeDownloader).should_receive(:new).with(["repose_server"]).and_return(repose)
        repose.should_receive(:logger=)
        repose.should_receive(:download).with("URI", Proc).and_yield("test")
        flexmock(FileUtils).should_receive(:mkdir_p).with(File.dirname("/path/to/out/file")).and_return(true)
        flexmock(File).should_receive(:open).with("/path/to/out/file", "wb", Proc).and_yield(file)
        file.should_receive(:write).with("test")
        repose.should_receive(:details).and_return("detais")
        run_repose_get_manager("--resource URI --out-file /path/to/out/file repose_server".split(" "))
      end
    end
  end
end
