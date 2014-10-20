#
# Copyright (c) 2012-2013 RightScale Inc
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

require ::File.expand_path('../spec_helper', __FILE__)
require ::File.normalize_path('../../../lib/clouds/metadata_sources/azure_metadata_source', __FILE__)
require 'tmpdir'
require 'openssl'
require 'base64'
require 'digest/sha1'
require 'digest/md5'

module RightScale
  module AzureMetadataSourceSpec

    # Windows changes the ST=CA portion of our issuer name to S=CA at some point.
    ISSUER_STATE_KEY = ::RightScale::Platform.windows? ? 'S' : 'ST'
    CLOUD_METADATA_CERT_ISSUER = "O=RightScale, C=US, #{ISSUER_STATE_KEY}=CA, CN=cloud certificate_metadata_source_spec"
    USER_METADATA_CERT_ISSUER = "O=RightScale, C=US, #{ISSUER_STATE_KEY}=CA, CN=user certificate_metadata_source_spec"
    LOCAL_MACHINE_CERT_STORE = "cert:/LocalMachine/My"

    DHCP_RESP = "\x02\x01\x06\x00\x96\x99\xE5\x82\x00\x00\x00\x00\x00\x00\x00\x00dG\xB0\x0FdG\x02\"dG\xB0\x01\x00\r:0\x06\x7F\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00RD90E2BA3D0E34\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00c\x82Sc5\x01\x026\x04dG\x02\"\x06\x04dG\xB0\x96\xF5\x04dG\xB0\x96\x0F$a-459212403.d3.internal.cloudapp.net\x01\x04\xFF\xFF\xFE\x00:\x04\xFF\xFF\xFF\xFF;\x04\xFF\xFF\xFF\xFF3\x04\xFF\xFF\xFF\xFF\x03\x04dG\xB0\x01\xFF"

    # Note: this is embedded in the DHCP resp above. This is an actual resp and in binary format so don't mess with it!
    FABRIC_CONTROLLER_IP='100.71.176.150'
    AZURE_INSTANCE_ID='i-953500757'
    AZURE_SERVICE_NAME='a-459212403'

    CLOUD_METADATA_SUBJECT_TEXT = <<EOF
instance_id=#{AZURE_INSTANCE_ID}
service_name=#{AZURE_SERVICE_NAME}
public_fqdn=#{AZURE_SERVICE_NAME}.cloudapp.net
public_ip=1.2.3.4
private_ip=10.11.12.13
EOF

  USER_METADATA_SUBJECT_TEXT = <<EOF
RS_rn_url=amqp://1234567890@broker1-2.rightscale.com/right_net
RS_rn_id=1234567890
RS_server=my.rightscale.com
RS_rn_auth=1234567890
RS_api_url=https://my.rightscale.com/api/inst/ec2_instances/1234567890
RS_rn_host=:1,broker1-1.rightscale.com:0
RS_version=5.8.0
RS_sketchy=sketchy4-2.rightscale.com
RS_token=1234567890
EOF

    WRITE_CERT_POWERSHELL_SCRIPT = <<EOF
try
{
  # requires Win2008+
  if ([Int32]::Parse((Get-WmiObject Win32_OperatingSystem).Version.split('.')[0]) -lt 6)
  {
    throw "This version of Windows is not supported."
  }

  # check arguments.
  if ($args.length -lt 3)
  {
    write-output "Usage: write_cert <subject text> <cert issuer> <cert file path>"
    exit 100
  }
  $SUBJECT_TEXT = $args[0]
  $CERT_ISSUER = $args[1]
  $OUTPUT_CERT_PATH = $args[2]

  $Subject = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($SUBJECT_TEXT))
  $KeyLength = 1024
  $NotBefore = [DateTime]::Now
  $NotAfter = $NotBefore.AddDays(1)

  # create Subject field in X.500 format using the following interface:
  # http://msdn.microsoft.com/en-us/library/aa377051(VS.85).aspx
  $SubjectDN = New-Object -ComObject X509Enrollment.CX500DistinguishedName
  $SubjectDN.Encode("CN=$Subject", 0x0)
  $IssuerDN = New-Object -ComObject X509Enrollment.CX500DistinguishedName
  $IssuerDN.Encode($CERT_ISSUER, 0x0)

  # generate Private key as follows:
  # http://msdn.microsoft.com/en-us/library/aa378921(VS.85).aspx
  $PrivateKey = New-Object -ComObject X509Enrollment.CX509PrivateKey
  $PrivateKey.ProviderName = "Microsoft Base Cryptographic Provider v1.0"

  # private key is supposed for signature: http://msdn.microsoft.com/en-us/library/aa379409(VS.85).aspx
  $PrivateKey.KeySpec = 0x2
  $PrivateKey.Length = $KeyLength

  # key will be stored in localmachine certificate store
  $PrivateKey.MachineContext = $TRUE
  $PrivateKey.Create()

  # now we need to create certificate request template using the following interface:
  # http://msdn.microsoft.com/en-us/library/aa377124(VS.85).aspx
  $Cert = New-Object -ComObject X509Enrollment.CX509CertificateRequestCertificate
  $Cert.InitializeFromPrivateKey(0x2, $PrivateKey, "")
  $Cert.Subject = $SubjectDN
  $Cert.Issuer = $IssuerDN
  $Cert.NotBefore = $NotBefore
  $Cert.NotAfter = $NotAfter
  $Cert.Encode()

  # now we need to process request and build end certificate using the following
  # interface: http://msdn.microsoft.com/en-us/library/aa377809(VS.85).aspx
  $Request = New-Object -ComObject X509Enrollment.CX509enrollment

  # process request
  $Request.InitializeFromRequest($Cert)

  # retrievecertificate encoded in Base64.
  $endCert = $Request.CreateRequest(0x1)

  # install certificate to localmachine store
  $Request.InstallResponse(0x2, $endCert, 0x1, "")

  # convert Bas64 string to a byte array and write cert file (.cer format in Windows)
  $bytes = [System.Convert]::FromBase64String($endCert)
  Set-Content -value $bytes -encoding byte -path $OUTPUT_CERT_PATH

  # remove unneeded installed copies from LocalMachine
  foreach ($container in "CA")
  {
    $x509store = New-Object Security.Cryptography.X509Certificates.X509Store $container, "LocalMachine"
    $x509store.Open([Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
    $x509store.Remove([Security.Cryptography.X509Certificates.X509Certificate2]$bytes)
    $x509store.Close()
  }
}
catch
{
  $ErrorActionPreference = "Continue"
  write-error $_
  exit 101
}

exit 0
EOF

    CLEAN_CERT_POWERSHELL_SCRIPT = <<EOF
try
{
  # requires Win2008+
  if ([Int32]::Parse((Get-WmiObject Win32_OperatingSystem).Version.split('.')[0]) -lt 6)
  {
    throw "This version of Windows is not supported."
  }

  # check arguments.
  if ($args.length -lt 1)
  {
    write-output "Usage: clean_cert <cert file path>"
    exit 100
  }
  $INPUT_CERT_PATH = $args[0]

  [byte[]] $bytes = get-content -encoding byte -path $INPUT_CERT_PATH

  foreach ($Container in "My")
  {
    $x509store = New-Object Security.Cryptography.X509Certificates.X509Store $Container, "LocalMachine"
    $x509store.Open([Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
    $x509store.Remove([Security.Cryptography.X509Certificates.X509Certificate2]$bytes)
    $x509store.Close()
  }
}
catch
{
  $ErrorActionPreference = "Continue"
  write-error $_
  exit 101
}

exit 0
EOF

  end
end

describe RightScale::MetadataSources::AzureMetadataSource do

  def platform_supported?
    (::RightScale::Platform.windows? && ::RightScale::Platform.release.split('.')[0].to_i >= 6 ) || ::RightScale::Platform.linux? || ::RightScale::Platform.darwin?
  end

  before(:each) do
    setup_metadata_provider
  end

  after(:each) do
    teardown_metadata_provider
  end

  # Parses newline-delimited metadata into a hash.
  #
  # === Parameters
  # tree_climber(MetadataTreeClimber):: tree climber
  # data(String):: raw data
  #
  # === Return
  # result(Hash):: Hash-like leaf value
  def create_userdata_leaf(tree_climber, data)
    result = tree_climber.create_branch
    ::RightScale::CloudUtilities.split_metadata(data, '&', result)
    result
  end

  def create_metadata_leaf(tree_climber, data)
    result = tree_climber.create_branch
    data.each do |k, v|
      # Make sure we coerce into strings. The json blob returned here auto-casts
      # types which will mess up later steps
      result[k.to_s.strip] = v.to_s.strip
    end
    result
  end

  def setup_metadata_provider
    @test_output_dir = ::File.join(::RightScale::Platform.filesystem.temp_dir, "certificate_metadata_source_spec_F2A81D8149D97AFA8625AECE4A98DA81")
    ::FileUtils.mkdir_p(@test_output_dir)
    @logger = flexmock('logger', 'info' => '', 'debug' => '')

    @user_metadata_cert_issuer = ::RightScale::AzureMetadataSourceSpec::USER_METADATA_CERT_ISSUER
    @user_metadata_cert_file_path = ::File.join(@test_output_dir, 'user.cer')
    @user_metadata_cert_store = ::RightScale::Platform.windows? ? ::RightScale::AzureMetadataSourceSpec::LOCAL_MACHINE_CERT_STORE : @user_metadata_cert_file_path

    # metadata source
    @metadata_source = ::RightScale::MetadataSources::AzureMetadataSource.new(
      :cloud_metadata_root_path => ::RightScale::Cloud::DEFAULT_CLOUD_METADATA_ROOT_PATH,
      :user_metadata_cert_store => @user_metadata_cert_store,
      :user_metadata_cert_issuer => @user_metadata_cert_issuer,
      :user_metadata_root_path => ::RightScale::Cloud::DEFAULT_USER_METADATA_ROOT_PATH,
      :logger => @logger)
    # tree climbers
    cloud_metadata_tree_climber = ::RightScale::MetadataTreeClimber.new(
      :root_path => ::RightScale::Cloud::DEFAULT_CLOUD_METADATA_ROOT_PATH,
      :user_metadata_root_path => ::RightScale::Cloud::DEFAULT_USER_METADATA_ROOT_PATH,
      :logger => @logger,
      :has_children_override => lambda{ |x, y, z| false },
      :create_leaf_override => method(:create_metadata_leaf))
    user_metadata_tree_climber = ::RightScale::MetadataTreeClimber.new(
      :root_path => ::RightScale::Cloud::DEFAULT_USER_METADATA_ROOT_PATH,
      :user_metadata_root_path => ::RightScale::Cloud::DEFAULT_USER_METADATA_ROOT_PATH,
      :logger => @logger,
      :create_leaf_override => method(:create_userdata_leaf))
    # cloud metadata
    @cloud_metadata_provider = ::RightScale::MetadataProvider.new
    @cloud_metadata_provider.metadata_source = @metadata_source
    @cloud_metadata_provider.metadata_tree_climber = cloud_metadata_tree_climber

    # user metadata
    @user_metadata_provider = ::RightScale::MetadataProvider.new
    @user_metadata_provider.metadata_source = @metadata_source
    @user_metadata_provider.metadata_tree_climber = user_metadata_tree_climber
  end

  def teardown_metadata_provider
    clean_cert(@user_metadata_cert_file_path) if File.file?(@user_metadata_cert_file_path)
    FileUtils.rm_rf(@test_output_dir) if File.directory?(@test_output_dir)
    @metadata_source.finish
    @metadata_source = nil
    @cert_file_path = nil
    @logger = nil
    @cloud_metadata_cert_store = nil
    @cloud_metadata_cert_issuer = nil
    @user_metadata_cert_store = nil
    @user_metadata_cert_issuer = nil
    @cloud_metadata_provider = nil
    @user_metadata_provider = nil
  end

  def verify_cloud_metadata(cloud_metadata)
    data = ::RightScale::AzureMetadataSourceSpec::CLOUD_METADATA_SUBJECT_TEXT
    compare_hash = ::RightScale::CloudUtilities.split_metadata(data, "\n", {})

    cloud_metadata.should == compare_hash
  end

  def verify_user_metadata(user_metadata)
    data = ::RightScale::AzureMetadataSourceSpec::USER_METADATA_SUBJECT_TEXT
    compare_hash = ::RightScale::CloudUtilities.split_metadata(data, "\n", {})

    user_metadata.should == compare_hash
  end

  def write_cert(subject_text, cert_issuer, output_cert_file_path)
    if ::RightScale::Platform.windows?
      write_cert_windows(subject_text, cert_issuer, output_cert_file_path)
    else
      write_cert_linux(subject_text, cert_issuer, output_cert_file_path)
    end
  end

  def write_cert_windows(subject_text, cert_issuer, output_cert_file_path)
    Dir.mktmpdir do |dir|
      script_file_path = ::File.normalize_path(::File.join(dir, 'write_cert.ps1'))
      ::File.open(script_file_path, "w") { |f| f.write ::RightScale::AzureMetadataSourceSpec::WRITE_CERT_POWERSHELL_SCRIPT }
      cmd = ::RightScale::Platform.shell.format_shell_command(script_file_path, subject_text, cert_issuer, output_cert_file_path)
      result = `#{cmd}`
      if $?.success?
        message = result.to_s.strip
        message = "Cannot find \"#{output_cert_file_path}\"" if message.empty?
        fail message unless File.file?(output_cert_file_path)
      else
        result = result.to_s.strip
        result = "Failed to write metadata to cert given as \"#{cert_issuer}\" under \"#{LOCAL_MACHINE_CERT_STORE}\"." if result.empty?
        fail result
      end
    end
    true
  end

  def write_cert_linux(subject_text, cert_issuer, output_cert_file_path)
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    cert.subject = OpenSSL::X509::Name.parse("CN=#{Base64::encode64(subject_text)}")
    cert_issuer = cert_issuer.split(", ").sort
    cert_issuer = cert_issuer.push(cert_issuer.shift).join(", ")
    cert.issuer = OpenSSL::X509::Name.parse(cert_issuer)
    key = OpenSSL::PKey::RSA.generate(2048)
    cert.public_key = key.public_key
    cert.not_before = Time.now
    cert.not_after = Time.now + 3600*24*365*10
    cert.sign(key, OpenSSL::Digest::SHA1.new)
    data = cert.to_pem

    ::File.open(output_cert_file_path, "wb") { |f| f.write data }

    true
  end

  def clean_cert(cert_file_path)
    if ::RightScale::Platform.windows?
      clean_cert_windows(cert_file_path)
    else
      clean_cert_linux(cert_file_path)
    end
  end

  def clean_cert_windows(cert_file_path)
    Dir.mktmpdir do |dir|
      script_file_path = ::File.normalize_path(::File.join(dir, 'clean_cert.ps1'))
      ::File.open(script_file_path, "w") { |f| f.write ::RightScale::AzureMetadataSourceSpec::CLEAN_CERT_POWERSHELL_SCRIPT }
      cmd = ::RightScale::Platform.shell.format_shell_command(script_file_path, cert_file_path)
      result = `#{cmd}`
      if $?.success?
        FileUtils.rm(cert_file_path)
      else
        result = result.to_s.strip
        result = "Failed to clean certificate given as \"#{cert_file_path}\"." if result.empty?
        fail result
      end
    end
    true
  end

  def clean_cert_linux(cert_file_path)
    FileUtils.rm(cert_file_path)

    true
  end

  it 'should query azure fabric controller for metadata' do
    pending "Platform not supported" unless platform_supported?

    fabric_controller_ip = ::RightScale::AzureMetadataSourceSpec::FABRIC_CONTROLLER_IP
    flexmock(@cloud_metadata_provider.metadata_source).should_receive(:send_dhcp_request).
      and_return(::RightScale::AzureMetadataSourceSpec::DHCP_RESP)
    # Note: we don't fully mock the metadata service here, just mock out the final object returned.
    # We test SharedConfig parsing and what not in another azure related spec and don't
    # need to dupe that here.
    @shared_config = flexmock('shared_config', 
      'public_ssh_port'   => nil,
      'public_winrm_port' => nil,
      'instance_id'       => ::RightScale::AzureMetadataSourceSpec::AZURE_INSTANCE_ID,
      'public_ip'         => '1.2.3.4',
      'private_ip'        => '10.11.12.13',
      'service_name'      => ::RightScale::AzureMetadataSourceSpec::AZURE_SERVICE_NAME)
    flexmock(@cloud_metadata_provider.metadata_source).should_receive(:query_url).
      with(/#{fabric_controller_ip}/).
      and_return('<ContainerId>1</ContainerId><InstanceId>1</InstanceId><Incarnation>1</Incarnation>')
    flexmock(@cloud_metadata_provider.metadata_source).should_receive(:parse_shared_config).
      and_return(@shared_config)
    cloud_metadata = @cloud_metadata_provider.build_metadata
    verify_cloud_metadata(cloud_metadata)

  end

  it 'should return userdata when expected certs appear in cert store' do
    pending "Platform not supported" unless platform_supported?

    write_cert(::RightScale::AzureMetadataSourceSpec::USER_METADATA_SUBJECT_TEXT.split("\n").join('&'),
               ::RightScale::AzureMetadataSourceSpec::USER_METADATA_CERT_ISSUER,
               @user_metadata_cert_file_path)


    user_metadata = @user_metadata_provider.build_metadata
    verify_user_metadata(user_metadata)
  end

  it 'should raise QueryError when certificates are missing' do
    pending "Platform not supported" unless platform_supported?

    lambda{ cloud_metadata = @user_metadata_provider.build_metadata }.should raise_error(::RightScale::MetadataSource::QueryFailed)
  end

  it 'should return empty metadata when certificates are unspecified' do
    pending "Platform not supported" unless platform_supported?

    @metadata_source.user_metadata_cert_issuer = nil

    user_metadata = @user_metadata_provider.build_metadata
    user_metadata.should == {}
  end

end

