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

module RightScale

  # Implements a simple LRU cache: items that are the least accessed are
  # deleted first.
  class CertificateCache

    # Max number of items to keep in memory
    DEFAULT_CACHE_MAX_COUNT = 100

    # Initialize cache
    def initialize(max_count = DEFAULT_CACHE_MAX_COUNT)
      @items = {}
      @list = []
      @max_count = max_count
    end
    
    # Add item to cache
    def put(key, item)
      if @items.include?(key)
        delete(key)
      end
      if @list.size == @max_count
        delete(@list.first)
      end
      @items[key] = item
      @list.push(key)
      item
    end
    alias :[]= :put
    
    # Retrieve item from cache
    # Store item returned by given block if any
    def get(key)
      if @items.include?(key)
        @list.each_index do |i|
          if @list[i] == key
            @list.delete_at(i)
            break
          end
        end
        @list.push(key)
        @items[key]
      else
        return nil unless block_given?
         self[key] = yield
      end
    end
    alias :[] :get
    
    # Delete item from cache
    def delete(key)
      c = @items[key]
      if c
        @items.delete(key)
        @list.each_index do |i|
  	      if @list[i] == key
  	        @list.delete_at(i)
  	        break
  	      end
        end
        c
      end
    end

  end # CertificateCache

end # RightScale