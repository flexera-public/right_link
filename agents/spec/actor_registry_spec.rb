require File.join(File.dirname(__FILE__), '..', '..', 'spec', 'spec_helper')

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
    flexmock(RightScale::RightLinkLog).should_receive(:info)
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
    flexmock(RightScale::RightLinkLog).should_receive(:info).with("[actor] #{importer.class.to_s}")
    @registry.register(importer, nil)
  end

  it "should handle actors registered with a custom prefix" do
    importer = WebDocumentImporter.new
    @registry.register(importer, 'monkey')
    @registry.actor_for('monkey').should == importer
  end
  
end # RightScale::ActorRegistry
