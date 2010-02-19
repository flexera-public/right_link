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

describe RightScale::ActorRegistry do
  
  class ::WebDocumentImporter
    include RightScale::Actor
    expose :import, :cancel

    def import
      1
    end
    def cancel
      0
    end
  end

  module ::Actors
    class ComedyActor
      include RightScale::Actor
      expose :fun_tricks
      def fun_tricks
        :rabbit_in_the_hat
      end
    end
  end

  before(:each) do
    @registry = RightScale::ActorRegistry.new
  end

  it "should know about all services" do
    @registry.register(WebDocumentImporter.new, nil)
    @registry.register(Actors::ComedyActor.new, nil)
    @registry.services.sort.should == ["/actors/comedy_actor/fun_tricks", "/web_document_importer/cancel", "/web_document_importer/import"]
  end

  it "should not register anything except RightScale::Actor" do
    lambda { @registry.register(String.new, nil) }.should raise_error(ArgumentError)
  end

  it "should register an actor" do
    importer = WebDocumentImporter.new
    @registry.register(importer, nil)
    @registry.actors['web_document_importer'].should == importer
  end

  it "should log info message that actor was registered" do
    importer = WebDocumentImporter.new
    flexmock(RightScale::RightLinkLog).should_receive(:info).with("[actor] #{importer.class.to_s}").once
    @registry.register(importer, nil)
  end

  it "should handle actors registered with a custom prefix" do
    importer = WebDocumentImporter.new
    @registry.register(importer, 'monkey')
    @registry.actor_for('monkey').should == importer
  end
  
end # RightScale::ActorRegistry
