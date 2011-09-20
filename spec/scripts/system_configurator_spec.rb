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
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'scripts', 'system_configurator'))

describe RightScale::SystemConfigurator do
  context '.run' do
    it 'should read the options file'
    it 'should specify some default options'
    it 'should call the appropriate action function'
    it 'should return 2 if the action is disabled'
    it 'should return 1 on failure'
    it 'should return 0 on success'
  end

  context '#configure_ssh' do
    it 'should be tested'
  end
end
