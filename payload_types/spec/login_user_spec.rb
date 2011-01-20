#
# Copyright (c) 2009 RightScale Inc
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

require File.join(File.dirname(__FILE__), 'spec_helper')
require 'json/ext'

# copy of the old model for RightScale::LoginUser before the public_keys member
# was added.
module LoginUserSpec
  class LoginUserBeforePublicKeys
    include RightScale::Serializable

    attr_accessor :uuid, :username, :public_key, :common_name, :superuser, :expires_at

    def initialize(*args)
      @uuid        = args[0]
      @username    = args[1]
      @public_key  = args[2]
      @common_name = args[3] || ''
      @superuser   = args[4] || false
      @expires_at  = Time.at(args[5]) if args[5] && (args[5] != 0)
    end

    def serialized_members
      [ @uuid, @username, @public_key, @common_name, @superuser, @expires_at.to_i ]
    end
  end
end

describe RightScale::LoginUser do

  # ensures that the serialization downgrade case works.
  def test_serialization_downgrade(user, public_key)
    json = user.to_json
    old_json = json.gsub("RightScale::LoginUser", "LoginUserSpec::LoginUserBeforePublicKeys")
    old_user = JSON.parse(old_json)
    old_user.class.should == LoginUserSpec::LoginUserBeforePublicKeys
    old_user.public_key.should == public_key
  end

  it 'should serialize old version without public_keys member' do
    num = rand(2**32).to_s(32)
    pub = rand(2**32).to_s(32)
    public_key = "ssh-rsa #{pub} #{num}@rightscale.com"
    user = LoginUserSpec::LoginUserBeforePublicKeys.new("v0-#{num}", "rs-#{num}", public_key, "#{num}@rightscale.old", true, nil)
    json = user.to_json
    json = json.gsub("LoginUserSpec::LoginUserBeforePublicKeys", "RightScale::LoginUser")
    user = JSON.parse(json)
    user.public_key.should == public_key
    user.public_keys.should == [public_key]
    test_serialization_downgrade(user, public_key)
  end

  it 'should serialize current version with single public_key' do
    num = rand(2**32).to_s(32)
    pub = rand(2**32).to_s(32)
    public_key = "ssh-rsa #{pub} #{num}@rightscale.com"
    user = RightScale::LoginUser.new("v0-#{num}", "rs-#{num}", public_key, "#{num}@rightscale.old", true, nil, nil)
    json = user.to_json
    user = JSON.parse(json)
    user.class.should == RightScale::LoginUser
    user.public_key.should == public_key
    user.public_keys.should == [public_key]
    test_serialization_downgrade(user, public_key)
  end

  it 'should serialize current version with multiple public_keys' do
    num = rand(2**32).to_s(32)
    public_keys = []
    3.times do
      pub = rand(2**32).to_s(32)
      public_keys << "ssh-rsa #{pub} #{num}@rightscale.com"
    end
    new_user = RightScale::LoginUser.new("v0-#{num}", "rs-#{num}", nil, "#{num}@rightscale.old", true, nil, public_keys)
    new_user.public_key.should == public_keys.first
    new_user.public_keys.should == public_keys
    test_serialization_downgrade(new_user, public_keys.first)
  end

end
