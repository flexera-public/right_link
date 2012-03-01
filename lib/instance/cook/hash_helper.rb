module RightScale
  #
  # collection of utilities for hashes
  #
  class HashHelper

    RECURSIVE_MERGE_PROC = Proc.new { |key, oldval, newval|
      if hash?(oldval) && hash?(newval)
        oldval.merge(newval, &RECURSIVE_MERGE_PROC)
      else
        newval
      end
    }

    # Perform a deep merge between given hashes
    #
    # === Parameters
    # first(Hash):: Hash to be merged into (modifies it)
    # second(Hash):: Merged in hash
    #
    # === Return
    # first(Hash):: Merged hash
    def self.deep_merge!(first, second)
      first.merge!(second, &RECURSIVE_MERGE_PROC)
    end

    # Check whether given Ruby is a Hash implementation
    # Supports Hash and Mash
    #
    # === Parameters
    # o(Object):: Object to be tested
    #
    # === Return
    # true:: If 'o' is a Hash or a Mash
    # false:: Otherwise
    def self.hash?(o)
      o.respond_to?(:has_key?)
    end

    # Produce a patch from two hashes
    # Patch is a hash with the following keys:
    #   - :diff:: Hash with key common to both input hashes and value composed of the corresponding
    #             different values: { :left => <left value>, :right => <right value> }
    #   - :left_only:: Hash composed of items only found in left hash
    #   - :right_only:: Hash composed of items only found in right hash
    #
    # === Parameters
    # left(Hash):: Diff left side
    # right(Hash):: Diff right side
    #
    # === Return
    # res(Hash):: Resulting diff hash
    def self.create_patch(left, right)
      res = empty_patch
      right.each do |k, v|
        if left.include?(k)
          if hash?(v) && hash?(left[k])
            patch = create_patch(left[k], v)
            res[:right_only].merge!({k => patch[:right_only]}) unless patch[:right_only].empty?
            res[:left_only].merge!({k => patch[:left_only]}) unless patch[:left_only].empty?
            res[:diff].merge!({k => patch[:diff]}) unless patch[:diff].empty?
          elsif v != left[k]
            res[:diff].merge!({k => { :left => left[k], :right => v}})
          end
        else
          res[:right_only].merge!({ k => v })
        end
      end
      left.each { |k, v| res[:left_only].merge!({ k => v }) unless right.include?(k) }
      res
    end

    # Empty patch factory
    #
    # === Return
    # p(Hash):: Empty patch hash
    def self.empty_patch
      p = { :diff => {}, :left_only => {}, :right_only => {} }
    end

    # Perform 3-way merge using given target and patch
    # values in target whose keys are in :left_only component of patch are removed
    # values in :right_only component of patch get deep merged into target
    # values in target whose keys are in :diff component of patch and which are identical to left side of patch
    # get overwritten with right side of patch
    #
    # === Parameters
    # target(Hash):: Target hash that patch will be applied to
    # patch(Hash):: Patch to be applied
    #
    # === Return
    # res(Hash):: Result of 3-way merge
    def self.apply_patch(target, patch)
      res = deep_dup(target)
      deep_remove!(res, patch[:left_only])
      deep_merge!(res, patch[:right_only])
      apply_diff!(res, patch[:diff])
      res
    end

    # Deep copy of given hash
    # Hash values should be strings, arrays or hashes
    #
    # === Parameters
    # hash(Hash|Mash):: Hash to be deeply copied
    #
    # === Return
    # res(Hash):: Deep copy
    def self.deep_dup(target)
      res = {}
      target.each do |k, v|
        if hash?(v)
          res[k] = deep_dup(v)
        else
          res[k] = (v.duplicable? ? v.dup : v)
        end
      end
      res
    end

    # Remove recursively values that exist in both remove and target from target
    #
    # === Parameters
    # target(Hash):: Hash to remove values from
    # remove(Hash):: Hash containing values to be removed
    #
    # === Return
    # target(Hash):: Modified target hash with values from remove hash removed
    def self.deep_remove!(target, remove)
      remove.each do |k, v|
        if target.include?(k)
          if target[k] == v
            target.delete(k)
          elsif hash?(v) && hash?(target[k])
            deep_remove!(target[k], v)
          end
        end
      end
      target
    end

    # Recursively apply diff component of patch
    #
    # === Parameters
    # target(Hash):: Hash that is modified according to given diff
    # diff(Hash):: :diff component of patch created via 'create_patch'
    #
    # === Return
    # target(Hash):: Modified target hash
    def self.apply_diff!(target, diff)
      diff.each do |k, v|
        if v[:left] && v[:right]
          target[k] = v[:right] if v[:left] == target[k]
        elsif target.include?(k)
          apply_diff!(target[k], v)
        end
      end
      target
    end
  end
end
