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

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'spec_helper'))
require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'lib', 'instance', 'cook'))

describe RightScale::CookbookPathMapping do
  [[nil, nil, nil, ""],
   [nil, nil, "1", "/1"],
   [nil, nil, "1/2", "/1/2"],
   [nil, nil, "/1/2", "/1/2"],
   [nil, nil, "/1/2/", "/1/2"],
   [nil, "8675309", "1/2", "/8675309/1/2"],
   [nil, "8675309/34", "1/2", "/8675309/34/1/2"],
   ["/root", "8675309/34", "1/2", "/root/8675309/34/1/2"],
   ["/root", nil, "1/2", "/root/1/2"],
  ].each do |args|
    it "repose mapping with '#{args[0..2].join(",").gsub(",", "', '")}' should be #{args[3]}" do
      RightScale::CookbookPathMapping.repose_path(args[0], args[1], args[2]).should == args[3]
    end
  end

  [[nil, nil, ""],
   [nil, "1", "/1"],
   [nil, "1/2", "/1/2"],
   [nil, "/1/2", "/1/2"],
   [nil, "/1/2/", "/1/2"],
   ["/8675309", "1/2", "/8675309/1/2"],
   ["/8675309/34", "1/2", "/8675309/34/1/2"],
   ["8675309/34", "1/2", "8675309/34/1/2"],
   ["1/2", nil,"1/2"],
  ].each do |args|
    it "checkout mapping with '#{args[0..1].join(",").gsub(",", "', '")}' should be #{args[2]}" do
      RightScale::CookbookPathMapping.checkout_path(args[0], args[1]).should == args[2]
    end
  end
end
