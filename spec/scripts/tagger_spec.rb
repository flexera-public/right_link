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
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'scripts', 'tagger'))

module RightScale
  describe Tagger do
    context 'version' do
      it 'does nothing' do
        class Tagger
          def test_version
            version
          end
        end
        
        subject.test_version.should match /rs_tag \d+\.\d+\.?\d* - RightLink's tagger \(c\) 2011 RightScale/
      end
    end
  end
end