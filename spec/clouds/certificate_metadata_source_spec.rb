#
# Copyright (c) 2011 RightScale Inc
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
require File.join(File.dirname(__FILE__), '..', '..', 'lib', 'clouds', 'metadata_sources', 'certificate_metadata_source')
require 'tmpdir'

module RightScale
  module CertificateMetadataSourceSpec

    CLOUD_METADATA_CERT_ISSUER = "O=RightScale, C=US, S=CA, CN=cloud certificate_metadata_source_spec"
    USER_METADATA_CERT_ISSUER = "O=RightScale, C=US, S=CA, CN=user certificate_metadata_source_spec"
    LOCAL_MACHINE_CERT_STORE = "cert:/LocalMachine/My"

    CLOUD_METADATA_SUBJECT_TEXT = <<EOF
public-hostname=myCloud-1-2-3-4.com
public-ip=1.2.3.4
private-ip=10.11.12.13
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

describe RightScale::MetadataSources::CertificateMetadataSource do

  def platform_supported?
    ::RightScale::Platform.windows? && ::RightScale::Platform.release.split('.')[0].to_i >= 6
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
  def create_metadata_leaf(tree_climber, data)
    result = tree_climber.create_branch
    ::RightScale::CloudUtilities.split_metadata(data, '&', result)
    result
  end

  def setup_metadata_provider
    @test_output_dir = ::File.join(::RightScale::Platform.filesystem.temp_dir, "certificate_metadata_source_spec_F2A81D8149D97AFA8625AECE4A98DA81")
    ::FileUtils.mkdir_p(@test_output_dir)
    @logger = flexmock('logger')

    @cloud_metadata_cert_store = ::RightScale::CertificateMetadataSourceSpec::LOCAL_MACHINE_CERT_STORE
    @cloud_metadata_cert_issuer = ::RightScale::CertificateMetadataSourceSpec::CLOUD_METADATA_CERT_ISSUER
    @cloud_metadata_cert_file_path = ::File.join(@test_output_dir, 'cloud.cer')

    @user_metadata_cert_store = ::RightScale::CertificateMetadataSourceSpec::LOCAL_MACHINE_CERT_STORE
    @user_metadata_cert_issuer = ::RightScale::CertificateMetadataSourceSpec::USER_METADATA_CERT_ISSUER
    @user_metadata_cert_file_path = ::File.join(@test_output_dir, 'user.cer')

    # metadata source
    @metadata_source = ::RightScale::MetadataSources::CertificateMetadataSource.new(:cloud_metadata_cert_store => @cloud_metadata_cert_store,
                                                                                    :cloud_metadata_cert_issuer => @cloud_metadata_cert_issuer,
                                                                                    :cloud_metadata_root_path => ::RightScale::Cloud::DEFAULT_CLOUD_METADATA_ROOT_PATH,
                                                                                    :user_metadata_cert_store => @user_metadata_cert_store,
                                                                                    :user_metadata_cert_issuer => @user_metadata_cert_issuer,
                                                                                    :user_metadata_root_path => ::RightScale::Cloud::DEFAULT_USER_METADATA_ROOT_PATH,
                                                                                    :logger => @logger)
    # tree climbers
    cloud_metadata_tree_climber = ::RightScale::MetadataTreeClimber.new(:root_path => ::RightScale::Cloud::DEFAULT_CLOUD_METADATA_ROOT_PATH,
                                                                        :user_metadata_root_path => ::RightScale::Cloud::DEFAULT_USER_METADATA_ROOT_PATH,
                                                                        :logger => @logger,
                                                                        :has_children_override => lambda{ false },
                                                                        :create_leaf_override => method(:create_metadata_leaf))
    user_metadata_tree_climber = ::RightScale::MetadataTreeClimber.new(:root_path => ::RightScale::Cloud::DEFAULT_USER_METADATA_ROOT_PATH,
                                                                       :user_metadata_root_path => ::RightScale::Cloud::DEFAULT_USER_METADATA_ROOT_PATH,
                                                                       :logger => @logger,
                                                                       :create_leaf_override => method(:create_metadata_leaf))
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
    clean_cert(@cloud_metadata_cert_file_path) if File.file?(@cloud_metadata_cert_file_path)
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
    data = ::RightScale::CertificateMetadataSourceSpec::CLOUD_METADATA_SUBJECT_TEXT
    compare_hash = ::RightScale::CloudUtilities.split_metadata(data, "\n", {})

    cloud_metadata.should == compare_hash
  end

  def verify_user_metadata(user_metadata)
    data = ::RightScale::CertificateMetadataSourceSpec::USER_METADATA_SUBJECT_TEXT
    compare_hash = ::RightScale::CloudUtilities.split_metadata(data, "\n", {})

    user_metadata.should == compare_hash
  end

  def write_cert(subject_text, cert_issuer, output_cert_file_path)
    Dir.mktmpdir do |dir|
      script_file_path = ::File.normalize_path(::File.join(dir, 'write_cert.ps1'))
      ::File.open(script_file_path, "w") { |f| f.write ::RightScale::CertificateMetadataSourceSpec::WRITE_CERT_POWERSHELL_SCRIPT }
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

  def clean_cert(cert_file_path)
    Dir.mktmpdir do |dir|
      script_file_path = ::File.normalize_path(::File.join(dir, 'clean_cert.ps1'))
      ::File.open(script_file_path, "w") { |f| f.write ::RightScale::CertificateMetadataSourceSpec::CLEAN_CERT_POWERSHELL_SCRIPT }
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

  it 'should return metadata when expected certs appear in cert store' do
    pending "Platform not supported" unless platform_supported?

    write_cert(::RightScale::CertificateMetadataSourceSpec::CLOUD_METADATA_SUBJECT_TEXT.split("\n").join('&'),
               ::RightScale::CertificateMetadataSourceSpec::CLOUD_METADATA_CERT_ISSUER,
               @cloud_metadata_cert_file_path)
    write_cert(::RightScale::CertificateMetadataSourceSpec::USER_METADATA_SUBJECT_TEXT.split("\n").join('&'),
               ::RightScale::CertificateMetadataSourceSpec::USER_METADATA_CERT_ISSUER,
               @user_metadata_cert_file_path)
    cloud_metadata = @cloud_metadata_provider.build_metadata
    verify_cloud_metadata(cloud_metadata)

    user_metadata = @user_metadata_provider.build_metadata
    verify_user_metadata(user_metadata)
  end

  it 'should raise QueryError when certificates are missing' do
    pending "Platform not supported" unless platform_supported?

    lambda{ cloud_metadata = @cloud_metadata_provider.build_metadata }.should raise_error(::RightScale::MetadataSource::QueryFailed)
    lambda{ cloud_metadata = @user_metadata_provider.build_metadata }.should raise_error(::RightScale::MetadataSource::QueryFailed)
  end

  it 'should return empty metadata when certificates are unspecified' do
    pending "Platform not supported" unless platform_supported?

    @metadata_source.cloud_metadata_cert_issuer = nil
    @metadata_source.user_metadata_cert_issuer = nil

    cloud_metadata = @cloud_metadata_provider.build_metadata
    cloud_metadata.should == {}

    user_metadata = @user_metadata_provider.build_metadata
    user_metadata.should == {}
  end

end
