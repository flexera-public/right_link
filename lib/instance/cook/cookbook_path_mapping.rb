#
# Copyright (c) 2009-2011 RightScale Inc
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
  # helpers for constructing various paths related to coookbooks
  class CookbookPathMapping
    # Constructs a repose download path for a given cookbook
    #
    # === Parameters
    # repose_root (String):: the root for all cookbooks downloaded with repose
    # repo_sha (String):: unique identifier for the repo containig the cookbook
    # position (String):: the relative path of the cookbook within the repo
    #
    # === Return
    #  (String):: full path to the repose download location for the given cookbook
    def self.repose_path(repose_root, repo_sha, position)
      build_path(repose_root, repo_sha, position)
    end

    # Constructs a cookbook checkout path for a given cookbook
    #
    # === Parameters
    # checkout_root (String):: the root of all checked out cookbooks
    # repo_dir (String):: root directory for all cookbooks in a the repo
    # position (String):: the relative path of the cookbook within the repo
    #
    # === Return
    #  (String):: full path to the checked out location for the given cookbook
    def self.checkout_path(repo_dir, position)
      build_path(repo_dir, position)
    end

    private
    # Combines the given path segments removing un needed separators and missing intermediate
    #
    # === Parameters
    # root (String):: the root of the path
    # sub (String):: middle section of the path
    # leaf (String):: end of the path
    #
    # === Return
    #  (String):: cleaned path, empty string is all params are nil
    def self.build_path(root="", sub="", leaf="")
      File.join(*([root || ""] + "#{sub || ""}".split('/') + "#{leaf || ""}".split('/')))
    end
  end
end