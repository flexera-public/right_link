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
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'scripts', 'log_level_manager'))

module RightScale
  describe RightLinkLogLevelManager do
    context 'version' do
      it 'reports RightLink version from gemspec' do
        class RightLinkLogLevelManager
          def test_version
            version
          end
        end
        
        subject.test_version.should match /rs_log_level \d+\.\d+\.?\d* - RightLink's log level \(c\) 2011 RightScale/
      end
    end
  end
end