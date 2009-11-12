require File.join(File.dirname(__FILE__), 'spec_helper')
require 'json/ext'

describe RightScale::Serializable do

  it 'should serialize' do
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

    b = RightScale::ExecutableBundle.new([fsi1, fsi2], 1234)
    fsi1.to_json
    b.to_json
  end
 
end
