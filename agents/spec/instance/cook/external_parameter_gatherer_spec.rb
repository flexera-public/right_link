#--
# Copyright: Copyright (c) 2010 RightScale, Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# 'Software'), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#++

require File.expand_path(File.join(File.dirname(__FILE__), "..", "..",
                                   "spec_helper"))
require File.expand_path(File.join(File.dirname(__FILE__), "..", "..", "..",
                                   "..", "payload_types", "lib",
                                   "payload_types"))
require File.expand_path(File.join(File.dirname(__FILE__), "..", "..", "..",
                                   "lib", "instance", "cook"))
require 'tmpdir'

module RightScale
  describe ExternalParameterGatherer do
    include SpecHelpers

    def run(gatherer)
      flexmock(AuditStub.instance).should_receive(:create_new_section).and_return(true).by_default
      flexmock(AuditStub.instance).should_receive(:append_info).and_return(true).by_default
      flexmock(AuditStub.instance).should_receive(:append_error).and_return(true).by_default
      flexmock(AuditStub.instance).should_receive(:update_status).and_return(true).by_default

      result = nil
      gatherer.callback { result = true ; EM.stop }
      gatherer.errback { result = false ; EM.stop }
      EM.run { EM.defer {  gatherer.run } }

      result
    end

    def secure_document_location(index)
      SecureDocumentLocation.new('777', (123+index).to_s, 12345, 'open sesame')
    end

    def secure_document(index)
      SecureDocument.new((123+index).to_s, 12345, 'shh, top secret!', 'default', 'text/plain', nil)
    end

    before(:each) do
      @serializer = Serializer.new

      @script  = RightScriptInstantiation.new
      @script.nickname  = 'Some Script!'
      @script.ready = true
      @script.parameters  = {'TEXT1' => 'this is cool', 'TEXT2' => 'this is cooler'}
      @script.source  = "#!/bin/bash\necho $TEXT1 $TEXT2"
      @script.attachments = []

      @recipe = RecipeInstantiation.new
      @recipe.nickname = 'db_hitchhikers_guide::install'
      @recipe.id = nil #Not a RightScript...
      @recipe.ready = true
      @recipe.attributes = {'so_long' => 'thanks for all the fish', 'has_towel' => 'true'}

      @options = {:cookie=>'chocolate chip', :listen_port=>'4242'}
    end

    context 'given no credentials' do
      it 'succeeds immediately' do
        @bundle = ExecutableBundle.new([@script, @recipe], [], 1234)
        @gatherer = ExternalParameterGatherer.new(@bundle, @options)
        result = run(@gatherer)
        @gatherer.failure_title.should be_nil
        @gatherer.failure_message.should be_nil
        result.should be_true
      end
    end

    context 'given credential locations' do
      context 'when fatal errors occur' do
        it 'fails gracefully' do
          creds = []
          (0..2).each { |j| creds << secure_document_location(j) }
          script = @script.dup
          script.external_inputs = {}
          recipe = @recipe.dup
          recipe.external_inputs = {}
          creds.each_with_index do |cred, j|
            p = "SECRET_CRED#{j}"
            script.external_inputs[p] = cred
            recipe.external_inputs[p] = cred
          end

          @bundle = ExecutableBundle.new([@script, @recipe], [], 1234)
          @bundle.executables << script
          @bundle.executables << recipe

          @gatherer = ExternalParameterGatherer.new(@bundle, @options)

          [0, 1].each do |j|
            payload = {:ticket=>'open sesame', :namespace=>'777', :names=>[ (123+j).to_s ]}
            data = @serializer.dump(OperationResult.success([ secure_document(j) ]))
            flexmock(@gatherer).should_receive(:send_idempotent_request).
              with('/vault/read_document', payload, Proc).and_yield(data).twice
          end

          [2].each do |j|
            payload = {:ticket=>'open sesame', :namespace=>'777', :names=>[ (123+j).to_s ]}
            data = @serializer.dump(OperationResult.error('too many cows on the moon'))
            flexmock(@gatherer).should_receive(:send_idempotent_request).
              with('/vault/read_document', payload, Proc).and_yield(data).twice
          end

          result = run(@gatherer)
          @gatherer.failure_title.should_not be_nil
          @gatherer.failure_message.should_not be_nil
          result.should be_false
        end
      end

      [1, 3, 10].each do |i|
        it "handles #{i} credentials" do

          creds = []
          (0...i).each { |j| creds << secure_document_location(j) }
          script = @script.dup
          script.external_inputs = {}
          recipe = @recipe.dup
          recipe.external_inputs = {}
          creds.each_with_index do |cred, j|
            p = "SECRET_CRED#{j}"
            script.external_inputs[p] = cred
            recipe.external_inputs[p] = cred
          end

          @bundle = ExecutableBundle.new([@script, @recipe], [], 1234)
          @bundle.executables << script
          @bundle.executables << recipe

          @gatherer = ExternalParameterGatherer.new(@bundle, @options)
          creds.each_with_index do |cred, j|
            payload = {:ticket=>'open sesame', :namespace=>'777', :names=>[ (123+j).to_s ]}
            data = @serializer.dump(OperationResult.success([ secure_document(j) ]))
            flexmock(@gatherer).should_receive(:send_idempotent_request).
              with('/vault/read_document', payload, Proc).and_yield(data).twice
          end

          result = run(@gatherer)
          @gatherer.failure_title.should be_nil
          @gatherer.failure_message.should be_nil
          result.should be_true

          @bundle.executables.each do |exe|
            case exe
              when RecipeInstantiation
                exe.attributes.values.count { |x| x == 'shh, top secret!' }.should == i
              when RightScriptInstantiation
                exe.parameters.values.count { |x| x == 'shh, top secret!' }.should == i
            end
          end
        end
      end
    end
  end
end