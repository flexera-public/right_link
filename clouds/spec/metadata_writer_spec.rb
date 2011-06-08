#
# Copyright (c) 2010 RightScale Inc
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
begin
  writers_path = File.join(File.dirname(__FILE__), '..', 'lib', 'clouds', 'metadata_writers')
  require File.normalize_path(File.join(writers_path, 'dictionary_metadata_writer'))
  require File.normalize_path(File.join(writers_path, 'ruby_metadata_writer'))
  require File.normalize_path(File.join(writers_path, 'shell_metadata_writer'))
end

module RightScale

  class MetadataWriterSpec

    METADATA = {'RS_mw_spec_x' => 'A1\'s\\', 'RS_mw_spec_YY' => " \"B2\" \n B3 ", 'RS_mw_spec_Zzz' => ''}
    FILTERED_METADATA = {'RS_mw_spec_x' => 'A1\'s\\', 'RS_mw_spec_YY' => "\"B2\"", 'RS_mw_spec_Zzz' => ''}
    RAW_METADATA = 'some raw metadata'

    GENERATION_COMMAND_OUTPUT = 'some-metadata-generation-command'
    GENERATION_COMMAND = "echo #{GENERATION_COMMAND_OUTPUT}"

  end

end

describe RightScale::MetadataWriter do

  before(:each) do
    @output_dir_path = File.join(::RightScale::RightLinkConfig[:platform].filesystem.temp_dir, 'rs_metadata_writers_output')
    FileUtils.rm_rf(@output_dir_path) if File.directory?(@output_dir_path)
  end

  after(:each) do
    FileUtils.rm_rf(@output_dir_path) if File.directory?(@output_dir_path)
    @output_dir_path = nil
  end

  it 'should write raw files by default' do
    writer = ::RightScale::MetadataWriter.new(:file_name_prefix => 'test', :output_dir_path => @output_dir_path)
    output_file_path = File.join(@output_dir_path, 'test.raw')
    writer.write(::RightScale::MetadataWriterSpec::RAW_METADATA)
    File.file?(output_file_path).should be_true
    contents = File.read(output_file_path)
    contents.should == ::RightScale::MetadataWriterSpec::RAW_METADATA
  end

  it 'should support override of read and write' do
    output = {}
    reader_writer = ::RightScale::MetadataWriter.new(
      :file_name_prefix => 'test',
      :output_dir_path => @output_dir_path,
      :write_override => lambda do |writer, metadata, subpath|
        writer.should == reader_writer
        output[subpath] = metadata
      end,
      :read_override => lambda do |reader, subpath|
        reader.should == reader_writer
        output[subpath]
       end
    )
    reader_writer.write(1, 'a')
    reader_writer.write(2, 'b/c')
    output.should == {"b/c"=>2, "a"=>1}
    reader_writer.read('a').should == 1
    reader_writer.read('b/c').should == 2
  end

  it 'should write dictionary files' do
    writer = ::RightScale::MetadataWriters::DictionaryMetadataWriter.new(:file_name_prefix => 'test', :output_dir_path => @output_dir_path)
    output_file_path = File.join(@output_dir_path, 'test.dict')
    writer.write(::RightScale::MetadataWriterSpec::METADATA)
    File.file?(output_file_path).should be_true
    contents = File.read(output_file_path)
    result = {}
    contents.each do |line|
      match = line.chomp.match(/^(.+)=(.*)$/)
      match.should_not be_nil
      result[match[1]] = match[2]
    end
    result.should == ::RightScale::MetadataWriterSpec::FILTERED_METADATA
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
      ::RightScale::MetadataWriterSpec::METADATA.each do |k, v|
        v = v.gsub(/\\|'/) { |c| "\\#{c}" }
        f.puts "exit 100 if ENV['#{k}'] != '#{v}'"
      end
      f.puts "exit 0"
    end
    interpreter = File.normalize_path(::RightScale::RightLinkConfig[:sandbox_ruby_cmd])
    output = `#{interpreter} #{verify_file_path}`
    $?.success?.should be_true
    output.strip.should == ::RightScale::MetadataWriterSpec::GENERATION_COMMAND_OUTPUT
  end

  it 'should write shell files' do
    writer = ::RightScale::MetadataWriters::ShellMetadataWriter.new(:file_name_prefix => 'test',
                                                                    :output_dir_path => @output_dir_path,
                                                                    :generation_command => ::RightScale::MetadataWriterSpec::GENERATION_COMMAND)
    output_file_path = File.join(@output_dir_path, "test#{writer.file_extension}")
    writer.write(::RightScale::MetadataWriterSpec::METADATA)
    File.file?(output_file_path).should be_true

    if ::RightScale::RightLinkConfig[:platform].windows?
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
        ::RightScale::MetadataWriterSpec::METADATA.each do |k, v|
          v = v.gsub(/\\|"/) { |c| "\\#{c}" }
          f.puts "if test \"$#{k}\" != \"#{v}\"; then exit 100; fi"
        end
        f.puts "exit 0"
      end
      interpreter = "/bin/bash"
    end
    output = `#{interpreter} #{verify_file_path}`
    $?.success?.should be_true
    output.strip.should == ::RightScale::MetadataWriterSpec::GENERATION_COMMAND_OUTPUT
  end

end
