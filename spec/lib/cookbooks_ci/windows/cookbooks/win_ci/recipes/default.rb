# Copyright (c) 2010-2011 RightScale Inc
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

require 'fileutils'

unless @node[:boot_run]

  # deploy web app zips to the wwwroot directory.
  powershell "Create CCrb environment" do
    # create .ssh directory for Administrator account (which is how CCrb runs).
    ssh_dir_path = File.expand_path(File.join(ENV['USERPROFILE'], '..', 'Administrator', '.ssh'))
    FileUtils.mkdir_p(ssh_dir_path)

    # write user-provided credentials to .ssh directory.
    credentials = @node[:win_ci][:credentials]
    credentials_path = File.expand_path(File.join(ssh_dir_path, "id_rsa"))
    File.open(credentials_path, "w") do |f|
      f.write(credentials)
    end

    # write user-provided known_hosts to .ssh directory.
    known_hosts = @node[:win_ci][:known_hosts]
    known_hosts_path = File.expand_path(File.join(ssh_dir_path, "known_hosts"))
    File.open(known_hosts_path, "w") do |f|
      f.puts(known_hosts)
    end

    # write public URL for CCrb to tools directory for configuring CCrb later.
    raise "Unable to resolve EC2_PUBLIC_HOSTNAME value." unless ENV['EC2_PUBLIC_HOSTNAME']
    dashboard_url = "http://ci-net-windows.test.rightscale.com:3333" #"http://#{ENV['EC2_PUBLIC_HOSTNAME']}:3333"

    seven_zip_exe_path = File.expand_path(File.join(File.dirname(__FILE__), '..', 'files', 'default', '7zip', '7z.exe')).gsub("/", "\\")
    intall_ccrb_bat_file_path = File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', '..', '..', 'tasks', 'windows', 'InstallCCrb.bat')).gsub("/", "\\")

    # FIX: the dns_made_easy_provider for v5.5 of right_link did not work for windows but should work for v5.6+
    register_ip = (@node[:win_ci][:dns_address_type] == 'private') ? ENV['EC2_LOCAL_IPV4'] : ENV['EC2_PUBLIC_IPV4']
    dns_made_easy_cmd = "curl -S -s --retry 7 -k -o - -g -f \"https://www.dnsmadeeasy.com/servlet/updateip?username=#{@node[:win_ci][:dns_user]}&password=#{@node[:win_ci][:dns_password]}&id=#{@node[:win_ci][:dns_id]}&ip=#{register_ip}\""
    result = `#{dns_made_easy_cmd}`
    if result =~ /success|error-record-ip-same/
      Chef::Log.info("DNSID #{@node[:win_ci][:dns_dns_id]} set to this instance IP: #{register_ip}")
    else
      raise "Error setting #{@node[:win_ci][:dns_dns_id]} to instance IP: #{register_ip}: Result: #{result}"
    end

    parameters('SEVEN_ZIP_EXE_PATH' => seven_zip_exe_path,
               'INSTALL_CCRB_BAT_FILE_PATH' => intall_ccrb_bat_file_path,
               'ADMIN_PASSWORD' => @node[:win_ci][:admin_password],
               'TOOLS_BUCKET' => @node[:win_ci][:tools_bucket],
               'PROJECTS' => @node[:win_ci][:projects],
               'DASHBOARD_URL' => dashboard_url)
    source_file_path = File.expand_path(File.join(File.dirname(__FILE__), '..', 'files', 'default', 'CCrb_deploy.ps1'))
    source_path(source_file_path)
  end

  @node[:boot_run] = true

end
