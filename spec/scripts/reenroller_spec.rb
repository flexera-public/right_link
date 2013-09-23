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
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'scripts', 'reenroller'))

module RightScale
  describe Reenroller do
    def run_reenroller(argv)
      replace_argv(argv)
      flexmock(subject).should_receive(:check_privileges).and_return(true)
      subject.run(subject.parse_args)
      return 0
    rescue SystemExit => e
      return e.status
    end

    def reenroll(resume=false)
      if RightScale::Platform::windows?
        flexmock(subject).should_receive(:cleanup_certificates).once
        flexmock(File).should_receive(:open).with(Reenroller::STATE_FILE, "w", Proc).once
        flexmock(subject).should_receive(:system).with('net start RightScale')
      else
        flexmock(subject).should_receive(:process_running?).and_return(false)
        flexmock(subject).should_receive(:system).with('/opt/rightscale/bin/rchk --stop').once
        flexmock(subject).should_receive(:cleanup_certificates).once
        if resume
          flexmock(subject).should_receive(:system).with("/etc/init.d/rightlink resume > /dev/null").once
        else
          flexmock(subject).should_receive(:system).with("/etc/init.d/rightlink start > /dev/null").once
        end
      end
      run_reenroller(resume ? '--resume': [])
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
      @error = []
      @output = []
      flexmock(STDOUT).should_receive(:puts).and_return { |message| @output << message; true }
      flexmock(STDOUT).should_receive(:print).and_return { |message| @output << message; true }
    end

    context 'resume option' do
      let(:short_name)    {'-r'}
      let(:long_name)     {'--resume'}
      let(:key)           {:resume}
      let(:value)         {''}
      let(:expected_value){true}
      it_should_behave_like 'command line argument'
    end

    context 'verbose option' do
      let(:short_name)    {'-v'}
      let(:long_name)     {'--verbose'}
      let(:key)           {:verbose}
      let(:value)         {''}
      let(:expected_value){true}
      it_should_behave_like 'command line argument'
    end

    context 'rs_reenroll --version' do
      it 'reports RightLink version from gemspec' do
        run_reenroller('--version')
        @output.join('\n').should match /rs_reenroll \d+\.\d+\.?\d* - RightLink's reenroller \(c\) 201\d RightScale/
      end
    end

    context 'rs_reenroll' do
      it 'should reenroll' do
        reenroll
      end
    end

    context 'rs_reenroll --resume' do
      it 'should resume' do
        reenroll(resume=true)
      end
    end
  end
end
