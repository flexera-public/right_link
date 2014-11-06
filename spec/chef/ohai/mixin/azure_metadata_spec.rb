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

require File.expand_path('../spec_helper', __FILE__)
require 'chef/ohai/mixin/azure_metadata'
require 'stringio'

describe ::Ohai::Mixin::AzureMetadata do

  context 'fetch_metadata' do
    #let (:dhcp_res_pkt) { "\x02\x01\x06\x00\x96\x99\xE5\x82\x00\x00\x00\x00\x00\x00\x00\x00dG\xB0\x0FdG\x02\"dG\xB0\x01\x00\r:0\x06\x7F\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00RD90E2BA3D0E34\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00c\x82Sc5\x01\x026\x04dG\x02\"\x06\x04dG\xB0\x96\xF5\x04dG\xB0\x96\x0F$a-459212403.d3.internal.cloudapp.net\x01\x04\xFF\xFF\xFE\x00:\x04\xFF\xFF\xFF\xFF;\x04\xFF\xFF\xFF\xFF3\x04\xFF\xFF\xFF\xFF\x03\x04dG\xB0\x01\xFF" }
    it "should have specs"
  end

  context 'SharedConfig' do
    let (:public_ip) { "104.45.227.59" }
    let (:public_ssh_port) { 56111 }
    let (:service_name) { "a-459212403" }
    let (:instance_id) { "i-9476a0cdf" }
    let (:private_ip) { "10.100.0.5" }
    let (:shared_config) do
<<-eos
<?xml version="1.0" encoding="utf-8"?>
<SharedConfig version="1.0.0.0" goalStateIncarnation="1">
<Deployment name="e28face85b5a4b3fb9cb67f6be591fc6" guid="{f119102e-e3cd-44ff-b584-bf842389b43d}" incarnation="0">
  <Service name="#{service_name}" guid="{00000000-0000-0000-0000-000000000000}" />
  <ServiceInstance name="e28face85b5a4b3fb9cb67f6be591fc6.0" guid="{1453d7fb-0dd6-4953-bb60-da6b50b28927}" />
</Deployment>
<Incarnation number="1" instance="#{instance_id}" guid="{a4b9535d-6efe-4be3-b1bb-d46f953c59d1}" />
<Role guid="{81f1430c-7998-5f40-4961-a5f30ca0af2c}" name="#{instance_id}" settleTimeSeconds="0" />
<Instances>
  <Instance id="#{instance_id}" address="#{private_ip}">
    <FaultDomains randomId="0" updateId="0" updateCount="0" />
    <InputEndpoints>
      <Endpoint name="SSH" address="#{private_ip}:22" protocol="tcp" hostName="a-443655003ContractContract" isPublic="true" loadBalancedPublicAddress="#{public_ip}:#{public_ssh_port}" enableDirectServerReturn="false" isDirectAddress="false" disableStealthMode="false">
        <LocalPorts>
          <LocalPortRange from="22" to="22" />
        </LocalPorts>
      </Endpoint>
    </InputEndpoints>
  </Instance>
</Instances>
</SharedConfig>
eos
    end
    subject do
      ::Ohai::Mixin::AzureMetadata::SharedConfig.new shared_config
    end
    context "#service_name" do
      it 'should return service_name' do
        subject.service_name.should == service_name
      end
    end

    context "#instance_id" do
      it 'should return instance_id' do
        subject.instance_id.should == instance_id
      end
    end

    context "#private_ip" do
      it 'should return private_ip' do
        subject.private_ip.should == private_ip
      end
    end

    context "#public_ip" do
      it 'should return public_ip' do
        subject.public_ip.should == public_ip
      end
    end

    context "#public_ssh_port" do
      it 'should return public_ssh_port' do
        subject.public_ssh_port.should == public_ssh_port
      end
    end
  end
end

