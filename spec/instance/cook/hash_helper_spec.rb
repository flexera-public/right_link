#
# Copyright (c) 2009-2012 RightScale Inc
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

describe RightScale::HashHelper do
  subject { RightScale::HashHelper }

  context '#deep_merge!' do
    { :identical =>{
        :left  => { :one => 1 },
        :right => { :one => 1 },
        :res   => { :one => 1 }
        },
      :disjoint => {
        :left  => { :one => 1 },
        :right => { :two => 1 },
        :res   => { :one => 1, :two => 1 }
        },
      :value_diff => {
        :left  => { :one => 1 },
        :right => { :one => 2 },
        :res   => { :one => 2 }
        },
      :recursive_disjoint => {
        :left  => { :one => { :a => 1, :b => 2 }, :two => 3 },
        :right => { :one => { :a => 1 }, :two => 3 },
        :res   => { :one => { :a => 1, :b => 2 }, :two => 3 }
        },
      :recursive_value_diff => {
        :left  => { :one => { :a => 1, :b => 2 }, :two => 3 },
        :right => { :one => { :a => 1, :b => 3 }, :two => 3 },
        :res   => { :one => { :a => 1, :b => 3 }, :two => 3 }
        },
      :recursive_disjoint_and_value_diff => {
        :left  => { :one => { :a => 1, :b => 2, :c => 3 }, :two => 3, :three => 4 },
        :right => { :one => { :a => 1, :b => 3, :d => 4 }, :two => 5, :four => 6 },
        :res   => { :one => { :a => 1, :b => 3, :c => 3 , :d => 4 }, :two => 5, :three => 4, :four => 6 }
        }
    }.each_pair do |name, data|
      it "should merge #{name} hashes" do
        subject.deep_merge!(data[:left], data[:right]).should == data[:res]
      end
    end
  end

  context "#create_patch" do
    {
      :identical => {
        :left  => { :one => 1 },
        :right => { :one => 1 },
        :res   => { :left_only  => {},
                    :right_only => {},
                    :diff       => {} }
        },
      :disjoint=> {
        :left  => { :one => 1 },
        :right => { :two => 1 },
        :res   => { :left_only  => { :one => 1},
                    :right_only => { :two => 1},
                    :diff       => {} }
        },
      :value_diff => {
        :left  => { :one => 1 },
        :right => { :one => 2 },
        :res   => { :left_only  => {},
                    :right_only => {},
                    :diff       => { :one => { :left => 1, :right => 2} } }
        },
      :recursive_disjoint => {
        :left  => { :one => { :a => 1, :b => 2 }, :two => 3 },
        :right => { :one => { :a => 1 }, :two => 3 },
        :res   => { :left_only  => { :one => { :b => 2 }},
                    :right_only => {},
                    :diff       => {} }
        },
      :recursive_value_diff => {
        :left  => { :one => { :a => 1, :b => 2 }, :two => 3 },
        :right => { :one => { :a => 1, :b => 3 }, :two => 3 },
        :res   => { :left_only  => {},
                    :right_only => {},
                    :diff       => { :one => { :b => { :left => 2, :right => 3 }} } }
        },
      :recursive_disjoint_and_value_diff => {
        :left  => { :one => { :a => 1, :b => 2, :c => 3 }, :two => 3, :three => 4 },
        :right => { :one => { :a => 1, :b => 3, :d => 4 }, :two => 5, :four => 6 },
        :res   => { :left_only  => { :one => { :c => 3 }, :three => 4 },
                    :right_only => { :one => { :d => 4 }, :four => 6 },
                    :diff       => { :one => { :b => { :left => 2, :right => 3 }}, :two => { :left => 3, :right => 5 }} }
        }
    }.each_pair do |name, data|
      it "should create patch for #{name} hashes" do
        subject.create_patch(data[:left], data[:right]).should == data[:res]
      end
    end
  end

  context '#apply_patch' do
    {
      :empty_patch => {
        :target => { :one => 1 },
        :patch  => { :left_only => {}, :right_only => {}, :diff => {} },
        :res    => { :one => 1}
      },
      :disjoint => {
        :target => { :one => 1 },
        :patch  => { :left_only => { :one => 2 }, :right_only => {}, :diff => { :one => { :left => 3, :right => 4 }} },
        :res    => { :one => 1 }
      },
      :removal => {
        :target => { :one => 1 },
        :patch  => { :left_only => { :one => 1 }, :right_only => {}, :diff => {} },
        :res    => {}
      },
      :addition => {
        :target => { :one => 1 },
        :patch  => { :left_only => {}, :right_only => { :two => 2 }, :diff => {} },
        :res    => { :one => 1, :two => 2 }
      },
      :substitution => {
        :target => { :one => 1 },
        :patch  => { :left_only => {}, :right_only => {}, :diff => { :one => { :left => 1, :right => 2} } },
        :res    => { :one => 2 }
      },
      :recursive_removal => {
        :target => { :one => { :a => 1, :b => 2 } },
        :patch  => { :left_only => { :one => { :a => 1 }}, :right_only => {}, :diff => {} },
        :res    => { :one => { :b => 2 } }
      },
      :recursive_addition => {
        :target => { :one => { :a => 1 } },
        :patch  => { :left_only => {}, :right_only => { :one => { :b => 2 } }, :diff => {} },
        :res    => { :one => { :a => 1, :b => 2 } }
      },
      :recursive_substitution => {
        :target => { :one => { :a => 1 } },
        :patch  => { :left_only => {}, :right_only => {}, :diff => { :one => { :a => { :left => 1, :right => 2 }} } },
        :res    => { :one => { :a => 2 } }
      },
      :combined => {
        :target => { :one => { :a => 1, :b => 2 } },
        :patch  => { :left_only => { :one => { :a => 1 } }, :right_only => { :one => { :c => 3 }}, :diff => { :one => { :b => { :left => 2, :right => 3 }} } },
        :res    => { :one => { :b => 3, :c => 3 } }
      }
    }.each_pair do |name, data|
      it "should apply #{name} patches" do
        subject.apply_patch(data[:target], data[:patch]).should == data[:res]
      end
    end
  end
end