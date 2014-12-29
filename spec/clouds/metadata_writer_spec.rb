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

METADATA_WRITERS_BASE_DIR = File.expand_path('../../../lib/clouds/metadata_writers', __FILE__)

require File.normalize_path(File.join(METADATA_WRITERS_BASE_DIR, 'json_metadata_writer'))
require File.normalize_path(File.join(METADATA_WRITERS_BASE_DIR, 'dictionary_metadata_writer'))
require File.normalize_path(File.join(METADATA_WRITERS_BASE_DIR, 'ruby_metadata_writer'))
require File.normalize_path(File.join(METADATA_WRITERS_BASE_DIR, 'shell_metadata_writer'))
require File.normalize_path(File.join(METADATA_WRITERS_BASE_DIR, 'raw_metadata_writer'))
require File.normalize_path(File.join(METADATA_WRITERS_BASE_DIR, 'dir_metadata_writer'))


module RightScale

  class MetadataWriterSpec

    METADATA = {'RS_mw_spec_x' => 'A1\'s\\', 'RS_mw_spec_YY' => " \"B2\" \n B3 ", 'RS_mw_spec_Zzz' => '', 'dir_a' => {'b' => "subdir_val", 'c' => "val1\nval2"}}
    UNFILTERED_METADATA = {'RS_MW_SPEC_X' => 'A1\'s\\', 'RS_MW_SPEC_YY' => " \"B2\" \n B3 ", 'RS_MW_SPEC_ZZZ' => '', 'RS_DIR_A_B' => 'subdir_val', 'RS_DIR_A_C' => "val1\nval2"}
    FILTERED_METADATA =   {'RS_MW_SPEC_X' => 'A1\'s\\', 'RS_MW_SPEC_YY' => "\"B2\"",         'RS_MW_SPEC_ZZZ' => '', 'RS_DIR_A_B' => 'subdir_val', 'RS_DIR_A_C' => "val1"}
    DICT_METADATA = "RS_MW_SPEC_X=A1's\\\nRS_MW_SPEC_YY=\"B2\"\nRS_MW_SPEC_ZZZ=\nRS_DIR_A_B=subdir_val\nRS_DIR_A_C=val1\n"
    RAW_METADATA = 'some raw metadata'

    GENERATION_COMMAND_OUTPUT = 'some-metadata-generation-command'
    GENERATION_COMMAND = "echo #{GENERATION_COMMAND_OUTPUT}"

  end

end

describe RightScale::MetadataWriter do

  before(:each) do
    @output_dir_path = File.join(::RightScale::Platform.filesystem.temp_dir, 'rs_metadata_writers_output')
    FileUtils.rm_rf(@output_dir_path) if File.directory?(@output_dir_path)
  end

  after(:each) do
    FileUtils.rm_rf(@output_dir_path) if File.directory?(@output_dir_path)
    @output_dir_path = nil
  end

  it 'should write raw files' do
    writer = ::RightScale::MetadataWriters::RawMetadataWriter.new(:file_name_prefix => 'test', :output_dir_path => @output_dir_path)
    output_file_path = File.join(@output_dir_path, 'test.raw')
    writer.write(::RightScale::MetadataWriterSpec::RAW_METADATA)
    File.file?(output_file_path).should be_true
    contents = File.read(output_file_path)
    contents.should == ::RightScale::MetadataWriterSpec::RAW_METADATA
  end

  it 'should write dictionary files' do
    writer = ::RightScale::MetadataWriters::DictionaryMetadataWriter.new(:file_name_prefix => 'test', :output_dir_path => @output_dir_path)
    output_file_path = File.join(@output_dir_path, 'test.dict')
    writer.write(::RightScale::MetadataWriterSpec::METADATA)
    File.file?(output_file_path).should be_true
    result = ::File.read(output_file_path)
    result.should == ::RightScale::MetadataWriterSpec::DICT_METADATA
  end


  it 'should write json files' do
    writer = ::RightScale::MetadataWriters::JsonMetadataWriter.new(:file_name_prefix => 'test', :output_dir_path => @output_dir_path)
    output_file_path = File.join(@output_dir_path, 'test.json')
    writer.write(::RightScale::MetadataWriterSpec::METADATA)
    File.file?(output_file_path).should be_true
    result = JSON.parse(::File.read(output_file_path))
    result.should == ::RightScale::MetadataWriterSpec::METADATA
  end

  it 'should write directory structured files' do
    writer = ::RightScale::MetadataWriters::DirMetadataWriter.new(:file_name_prefix => 'test',
                                                                   :output_dir_path => @output_dir_path,
                                                                   :generation_command => ::RightScale::MetadataWriterSpec::GENERATION_COMMAND)
    writer.write(::RightScale::MetadataWriterSpec::METADATA)

    output_dir = File.join(@output_dir_path, 'test')
    File.directory?(output_dir).should be_true


    output_file_dir_b = File.join(output_dir, "dir_a", "b")
    File.file?(output_file_dir_b).should be_true
    result_b = ::File.read(output_file_dir_b)
    result_b.should == ::RightScale::MetadataWriterSpec::METADATA['dir_a']['b']

    output_file_dir_c = File.join(output_dir, "dir_a", "c")
    File.file?(output_file_dir_c).should be_true
    result_c = ::File.read(output_file_dir_c)
    result_c.should == ::RightScale::MetadataWriterSpec::METADATA['dir_a']['c']

  end

  it 'should write ruby files' do
    writer = ::RightScale::MetadataWriters::RubyMetadataWriter.new(:file_name_prefix => 'test',
                                                                   :output_dir_path => @output_dir_path,
                                                                   :generation_command => ::RightScale::MetadataWriterSpec::GENERATION_COMMAND)
    output_file_path = File.join(@output_dir_path, 'test.rb')
    writer.write(::RightScale::MetadataWriterSpec::METADATA)
    File.file?(output_file_path).should be_true

    verify_file_path = File.join(@output_dir_path, 'verify.rb')
    File.open(verify_file_path, "w") do |f|
      f.puts "require \"#{output_file_path}\""
      ::RightScale::MetadataWriterSpec::UNFILTERED_METADATA.each do |k, v|
        v = v.gsub(/\\|'/) { |c| "\\#{c}" }
        f.puts "exit 100 if ENV['#{k}'] != '#{v}'"
      end
      f.puts "exit 0"
    end
    interpreter = File.normalize_path(RightScale::AgentConfig.ruby_cmd)
    output = `#{interpreter} #{verify_file_path}`
    $?.success?.should be_true
    output.strip.should == ::RightScale::MetadataWriterSpec::GENERATION_COMMAND_OUTPUT
  end

  it 'should write shell files' do
    writer = ::RightScale::MetadataWriters::ShellMetadataWriter.new(:file_name_prefix => 'test',
                                                                    :output_dir_path => @output_dir_path)
    output_file_path = File.join(@output_dir_path, "test#{writer.file_extension}")
    writer.write(::RightScale::MetadataWriterSpec::METADATA)
    File.file?(output_file_path).should be_true

    if ::RightScale::Platform.windows?
      verify_file_path = File.join(@output_dir_path, 'verify.bat')
      File.open(verify_file_path, "w") do |f|
        f.puts "@echo off"
        f.puts "call \"#{output_file_path}\""
        ::RightScale::MetadataWriterSpec::FILTERED_METADATA.each do |k, v|
          f.puts "if \"%#{k}%\" neq \"#{v}\" exit 100"
        end
        f.puts "exit 0"
      end
      interpreter = "cmd.exe /c"
    else
      verify_file_path = File.join(@output_dir_path, 'verify.sh')
      File.open(verify_file_path, "w") do |f|
        f.puts ". \"#{output_file_path}\""
        ::RightScale::MetadataWriterSpec::UNFILTERED_METADATA.each do |k, v|
          v = v.gsub(/\\|"/) { |c| "\\#{c}" }
          f.puts "if test \"$#{k}\" != \"#{v}\"; then exit 100; fi"
        end
        f.puts "exit 0"
      end
      interpreter = "/bin/bash"
    end
    output = `#{interpreter} #{verify_file_path}`
    $?.success?.should be_true
  end

end
