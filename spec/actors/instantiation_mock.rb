#
# Copyright (c) 2009-2011 RightScale Inc
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

module RightScale

  class InstantiationMock

    # Generate test script bundle
    def self.script_bundle(nick = "suzuki drz400sm (white)", nick2 = "second script on the hill")
      sample_script  = RightScale::RightScriptInstantiation.new
      sample_script2 = RightScale::RightScriptInstantiation.new
      sample_script2.nickname = nick2
      sample_script.nickname  = nick
      sample_script.ready = true
      sample_script2.ready = true

      sample_script.parameters  = {'SOME_SECRET_PARAMETER' => 'some secret value', 'OTHER_SECRET' => 'other secret value'}
      sample_script2.parameters = {'SOME_SECRET_PARAMETER' => 'some secret value', 'OTHER_SECRET' => 'other secret value'}
      sample_script.source  = "#!/bin/bash\necho 'ola'"
      sample_script2.source = "#!/bin/bash\necho 'ole'"

      sample_attach           = RightScale::RightScriptAttachment.new
      sample_attach.url       = "http://www.google.com/images/nav_logo4.png"
      sample_attach.file_name = "nav_logo4.png"

      sample_attach2           = RightScale::RightScriptAttachment.new
      sample_attach2.url       = "http://www.google.com/images/nav_logo4.png"
      sample_attach2.file_name = "nav_logosecond_script.png"

      sample_script.attachments  = [sample_attach, sample_attach2]
      sample_script2.attachments = [sample_attach2]

      RightScale::PayloadFactory.make_bundle(:executables => [sample_script, sample_script2])
    end

    # Generate array of test software repositories
    def self.repositories
      fsi1 = RightScale::SoftwareRepositoryInstantiation.new
      fsi1.name = "Yum::CentOS::Base"
      fsi1.base_urls = ["http://ec2-us-east-mirror.rightscale.com/centos",
                       "http://ec2-us-east-mirror1.rightscale.com/centos",
                       "http://ec2-us-east-mirror2.rightscale.com/centos", 
                       "http://ec2-us-east-mirror3.rightscale.com/centos"]

      fsi2 = RightScale::SoftwareRepositoryInstantiation.new
      fsi2.name = "Gems::RubyGems"
      fsi2.base_urls = ["http://ec2-us-east-mirror.rightscale.com/rubygems",
                       "http://ec2-us-east-mirror1.rightscale.com/rubygems",
                       "http://ec2-us-east-mirror2.rightscale.com/rubygems", 
                       "http://ec2-us-east-mirror3.rightscale.com/rubygems"]

      RightScale::RepositoriesBundle.new([fsi1, fsi2], 1234)   
    end

    # Generate a totally boring login policy
    def self.login_policy()
      lp = LoginPolicy.new(1234, Time.now, false)
    end
  end

end

