require File.join(File.dirname(__FILE__), 'spec_helper')

describe RightScale::EncryptedDocument do
  
  include SpecHelpers

  before(:all) do
    @test_data = "Test Data to Sign"
    @cert, @key = issue_cert
    @doc = RightScale::EncryptedDocument.new(@test_data, @cert)
  end

  it 'should create encrypted data' do
    @doc.encrypted_data.should_not be_nil
  end

  it 'should decrypt correctly' do
    @doc.decrypted_data(@key, @cert).should == @test_data
  end

end
