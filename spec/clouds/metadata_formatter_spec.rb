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

module RightScale

  class MetadataFormatterSpec

    METADATA = {'ABC' => ['easy', 123], :simple => "do re mi", 'abc_123' => {'baby' => [:you, :me, :girl] }}
    PREFIXED_METADATA = {'ABC' => ['easy', 123], :Ec2_simple => "do re mi", 'rs_abc_123' => {'baby' => [:you, :me, :girl] }}
    WITH_EMTPY_VALUES_METADATA = {'ABC' => [[]], :simple => "do re mi", 'empty' => '', 'abc_123' => {}}

  end

end

describe RightScale::MetadataFormatter do

  it 'should format metadata using the default prefix' do
    formatter = ::RightScale::MetadataFormatter.new
    result = formatter.format_metadata(::RightScale::MetadataFormatterSpec::METADATA)
    result.should == {"RS_ABC_0"=>"easy", "RS_ABC_1" => 123, "RS_SIMPLE"=>"do re mi", "RS_ABC_123_BABY_0"=>:you, "RS_ABC_123_BABY_1"=>:me, "RS_ABC_123_BABY_2"=>:girl}
  end

  it 'should skip empty values' do
    formatter = ::RightScale::MetadataFormatter.new(:formatted_path_prefix => "EC2_")
    result = formatter.format_metadata(::RightScale::MetadataFormatterSpec::WITH_EMTPY_VALUES_METADATA)
    result.should == {"EC2_SIMPLE"=>"do re mi", 'EC2_EMPTY' => ""}
  end


  it 'should format metadata using a custom prefix and preserve both custom and default prefix' do
    formatter = ::RightScale::MetadataFormatter.new(:formatted_path_prefix => "EC2_")
    result = formatter.format_metadata(::RightScale::MetadataFormatterSpec::PREFIXED_METADATA)
    result.should == {"EC2_ABC_0"=>"easy", "EC2_ABC_1" => 123, "EC2_SIMPLE"=>"do re mi", "RS_ABC_123_BABY_0"=>:you, "RS_ABC_123_BABY_1"=>:me, "RS_ABC_123_BABY_2"=>:girl}
  end

  it 'should support override of format_metadata' do
    overridden_formatter = ::RightScale::MetadataFormatter.new(
      :format_metadata_override => lambda do |formatter, metadata|
        formatter.should == overridden_formatter
        metadata.invert
      end
    )
    result = overridden_formatter.format_metadata(::RightScale::MetadataFormatterSpec::METADATA)
    result.should == {"do re mi"=>:simple, {"baby"=>[:you, :me, :girl]}=>"abc_123", ["easy", 123]=>"ABC"}
  end

end
