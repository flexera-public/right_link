#--
# Copyright (c) 2012 RightScale, Inc, All Rights Reserved Worldwide.
#
# THIS PROGRAM IS CONFIDENTIAL AND PROPRIETARY TO RIGHTSCALE
# AND CONSTITUTES A VALUABLE TRADE SECRET.  Any unauthorized use,
# reproduction, modification, or disclosure of this program is
# strictly prohibited.  Any use of this program by an authorized
# licensee is strictly subject to the terms and conditions,
# including confidentiality obligations, set forth in the applicable
# License Agreement between RightScale, Inc. and
# the licensee.
#++

require File.expand_path(File.join(File.dirname(__FILE__), 'spec_helper'))

describe RightScale::SystemConfiguration do
  it 'logs execution of reload action' do
    RightScale::SystemConfiguration.reload
  end
end