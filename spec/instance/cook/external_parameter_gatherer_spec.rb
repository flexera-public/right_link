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

require 'spec_helper'

require 'tmpdir'
require 'right_agent/core_payload_types'
require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'lib', 'instance', 'cook','audit_stub'))
require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'lib', 'instance', 'cook','external_parameter_gatherer'))

module RightScale
  describe ExternalParameterGatherer do
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

    def secure_document_location(index, targets=nil)
      SecureDocumentLocation.new('777', (123+index).to_s, 12345, 'open sesame', targets)
    end

    def secure_document(index)
      SecureDocument.new((123+index).to_s, 12345, 'shh, top secret!', 'default', 'text/plain', nil)
    end

    def special_script_with_external_inputs(count, targets=nil)
      external_inputs = []
      (0...count).each { |j| external_inputs << secure_document_location(j, targets) }
      script = @script.dup
      script.external_inputs = {}
      external_inputs.each_with_index do |cred, j|
        p = "SECRET_CRED#{j}"
        script.external_inputs[p] = cred
      end

      return [script, external_inputs]
    end

    def special_recipe_with_external_inputs(count, targets=nil)
      external_inputs = []
      (0...count).each { |j| external_inputs << secure_document_location(j, targets) }
      recipe = @recipe.dup
      recipe.external_inputs = {}
      external_inputs.each_with_index do |cred, j|
        p = "SECRET_CRED#{j}"
        recipe.external_inputs[p] = cred
      end

      return [recipe, external_inputs]
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
      context 'with no targets' do
        it 'sends requests with no target' do
          script, external_inputs = special_script_with_external_inputs(1, nil)
          @bundle = ExecutableBundle.new([script], [], 1234)
          @gatherer = ExternalParameterGatherer.new(@bundle, @options)

          nil_targets = {:targets=>nil}

          payload = {:ticket=>'open sesame', :namespace=>'777', :names=>[ (123).to_s ]}
          data = @serializer.dump(OperationResult.success([ secure_document(0) ]))
          flexmock(@gatherer).should_receive(:send_idempotent_request).
            with('/vault/read_documents', payload, nil_targets, Proc).and_yield(data)
        end
      end

      context 'with targets specified' do
        it 'sends requests to specific targets' do
          script, external_inputs = special_script_with_external_inputs(1, nil)
          @bundle = ExecutableBundle.new([script], [], 1234)
          @gatherer = ExternalParameterGatherer.new(@bundle, @options)

          one_target = {:targets=>'rs-steward-12345-1111'}

          payload = {:ticket=>'open sesame', :namespace=>'777', :names=>[ (123).to_s ]}
          data = @serializer.dump(OperationResult.success([ secure_document(0) ]))
          flexmock(@gatherer).should_receive(:send_idempotent_request).
            with('/vault/read_documents', payload, one_target, Proc).and_yield(data)
        end
      end

      context 'when fatal errors occur' do
        it 'fails RightScripts gracefully' do
          script, external_inputs = special_script_with_external_inputs(3)
          @bundle = ExecutableBundle.new([script], [], 1234)
          @gatherer = ExternalParameterGatherer.new(@bundle, @options)

          nil_targets = {:targets=>nil}

          [0, 1].each do |j|
            payload = {:ticket=>'open sesame', :namespace=>'777', :names=>[ (123+j).to_s ]}
            data = @serializer.dump(OperationResult.success([ secure_document(j) ]))
            flexmock(@gatherer).should_receive(:send_idempotent_request).
              with('/vault/read_documents', payload, nil_targets, Proc).and_yield(data)
          end

          [2].each do |j|
            payload = {:ticket=>'open sesame', :namespace=>'777', :names=>[ (123+j).to_s ]}
            data = @serializer.dump(OperationResult.error('too many cows on the moon'))
            flexmock(@gatherer).should_receive(:send_idempotent_request).
              with('/vault/read_documents', payload, nil_targets, Proc).and_yield(data)
          end

          result = run(@gatherer)
          @gatherer.failure_title.should_not be_nil
          @gatherer.failure_message.should_not be_nil
          result.should be_false
        end

        it 'fails recipes gracefully' do
          nil_targets = {:targets=>nil}

          recipe, external_inputs = special_recipe_with_external_inputs(3)

          @bundle = ExecutableBundle.new([recipe], [], 1234)
          @gatherer = ExternalParameterGatherer.new(@bundle, @options)

          [0, 1].each do |j|
            payload = {:ticket=>'open sesame', :namespace=>'777', :names=>[ (123+j).to_s ]}
            data = @serializer.dump(OperationResult.success([ secure_document(j) ]))
            flexmock(@gatherer).should_receive(:send_idempotent_request).
              with('/vault/read_documents', payload, nil_targets, Proc).and_yield(data)
          end

          [2].each do |j|
            payload = {:ticket=>'open sesame', :namespace=>'777', :names=>[ (123+j).to_s ]}
            data = @serializer.dump(OperationResult.error('too many cows on the moon'))
            flexmock(@gatherer).should_receive(:send_idempotent_request).
              with('/vault/read_documents', payload, nil_targets, Proc).and_yield(data)
          end

          result = run(@gatherer)
          @gatherer.failure_title.should_not be_nil
          @gatherer.failure_message.should_not be_nil
          result.should be_false
        end
      end

      [1, 3, 10].each do |i|
        it "handles #{i} credentials" do
          nil_targets = {:targets=>nil}

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
              with('/vault/read_documents', payload, nil_targets, Proc).and_yield(data).twice
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