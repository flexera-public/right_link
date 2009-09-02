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
#

module RightScale

  # Cookbook repository
  class CookbookRepository

    include Serializable

    # List of characters used to build cookbooks sha1 hash path component
    CHARS = ("a".."z").to_a + ("A".."Z").to_a + (0..9).to_a + ["_"]

    # <Symbol> Type of repository: one of :git, :svn, :download or :local
    # * :git denotes a 'git' repository that should be retrieved via 'git clone'
    # * :svn denotes a 'svn' repository that should be retrieved via 'svn checkout'
    # * :download denotes a tar ball that should be retrieved via HTTP GET (HTTPS if url starts with https://)
    # * :local denotes an already available cookbook (useful for testing)
    attr_accessor :repo_type

    # <String> URI to repository (e.g. git://github.com/opscode/chef-repo.git)
    attr_accessor :url

    # <String> git commit or svn branch that should be used to retrieve repository
    # Use 'master' for git and 'trunk' for svn if tag is nil.
    # Not used for raw repositories.
    attr_accessor :tag

    # <Array> Path to cookbooks inside repostory
    # Append to the location of the repository on disk prior to running chef.
    # Optional (use location of repository as cookbook path if nil)
    attr_accessor :cookbooks_path

    # <String> Private SSH key used to retrieve git repositories
    # Not used for svn and raw repositories.
    attr_accessor :ssh_key

    # <String> Username used to retrieve svn and raw repositories
    # Not used for git repositories.
    attr_accessor :username

    # <String> Password used to retrieve svn and raw repositories
    # Not used for git repositories.
    attr_accessor :password

    # Initialize fields from given arguments
    def initialize(*args)
      @repo_type      = args[0].to_sym
      @url            = args[1] if args.size > 1
      @tag            = args[2] if args.size > 2
      @cookbooks_path = args[3] if args.size > 3
      @ssh_key        = args[4] if args.size > 4
      @username       = args[5] if args.size > 5
      @password       = args[6] if args.size > 6
    end

    # Instantiate from hash
    # Keys of hash should be the corresponding symolized field name
    #
    # === Parameters
    # h<Hash>:: Hash of values used to initialize cookbook repository
    #
    # === Return
    # repo<RightScale::CookbookRepository>:: Corresponding instance
    def self.from_hash(h)
      repo = new(h[:repo_type], h[:url], h[:tag], h[:cookbooks_path], h[:ssh_key], h[:username], h[:password])
    end

    # Array of serialized fields given to constructor
    def serialized_members
      [ @repo_type, @url, @tag, @cookbooks_path, @ssh_key, @username, @password ]
    end

    # Serialize cookbook repo instantiation into filename compatible string
    #
    # === Return
    # ser<String>:: Serialized representation of cookbook repository
    def to_s
      base = @repo_type == :local ? 'local' : (@url.include?('://') ? @url[(@url.index('://')  + 3)..(@url.size - 1)] : @url)
      comps = base.split('/')
      ser = comps.map { |c| c.gsub(/[:&%\+\.]/, '_') }.join('_').gsub(/-+/, '_')
      ser += '_' + tag if tag
      if @cookbooks_path
        n = Digest::SHA1.hexdigest(@cookbooks_path.join("\n")).hex
        cbp_hash = []
        while n > 0
          cbp_hash << CHARS[n.divmod(CHARS.size)[1]]
          n = n.divmod(CHARS.size)[0]
        end
        ser += '_' + cbp_hash.to_s
      end
      ser
    end

  end
end
