require File.join(File.dirname(__FILE__), '..', '..', 'spec', 'spec_helper')

module RightScale
  
  # Add the ability to compare pings for test purposes
  class PingPacket
    def ==(other)
      @status == other.status && @identity == other.identity
    end
  end
  
end

describe RightScale::SecureSerializer do
  
  include RightScale::SpecHelpers

  before(:all) do
    @certificate, @key = issue_cert
    @store = RightScale::StaticCertificateStore.new(@certificate, @certificate)
    @identity = "id"
    @data = RightScale::PingPacket.new("Test", 0.5)
  end
  
  it 'should raise when not initialized' do
    lambda { RightScale::SecureSerializer.dump(@data) }.should raise_error
  end

  it 'should deserialize signed data' do
    RightScale::SecureSerializer.init(@identity, @certificate, @key, @store, false)
    data = RightScale::SecureSerializer.dump(@data)
    RightScale::SecureSerializer.load(data).should == @data
  end
  
  it 'should deserialize encrypted data' do
    RightScale::SecureSerializer.init(@identity, @certificate, @key, @store, true)
    data = RightScale::SecureSerializer.dump(@data)
    RightScale::SecureSerializer.load(data).should == @data
  end

end