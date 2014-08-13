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

require File.expand_path(File.join(File.dirname(__FILE__), 'spec_helper.rb'))
require 'chef/ohai/mixin/azure_metadata'
require 'stringio'

describe ::Ohai::Mixin::AzureMetadata do

  context 'fetch_metadata' do
    it "should have specs"
  end

  context 'SharedConfig' do
    let (:public_ip) { "168.62.10.167" }
    let (:public_ssh_port) { 56111 }
    let (:vm_name) { "a-443655003" }
    let (:private_ip) { "10.100.0.5" }
    let (:shared_config) do
<<-eos
<?xml version="1.0" encoding="utf-8"?>
<SharedConfig version="1.0.0.0" goalStateIncarnation="1">
<Deployment name="e28face85b5a4b3fb9cb67f6be591fc6" guid="{f119102e-e3cd-44ff-b584-bf842389b43d}" incarnation="0">
  <Service name="#{vm_name}" guid="{00000000-0000-0000-0000-000000000000}" />
  <ServiceInstance name="e28face85b5a4b3fb9cb67f6be591fc6.0" guid="{1453d7fb-0dd6-4953-bb60-da6b50b28927}" />
</Deployment>
<Incarnation number="1" instance="i-8e2f9b78a" guid="{a4b9535d-6efe-4be3-b1bb-d46f953c59d1}" />
<Role guid="{81f1430c-7998-5f40-4961-a5f30ca0af2c}" name="i-8e2f9b78a" settleTimeSeconds="0" />
<Instances>
  <Instance id="i-8e2f9b78a" address="#{private_ip}">
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
    context "#vm_name" do
      it 'should return vm_name' do
        subject.vm_name.should == vm_name
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

