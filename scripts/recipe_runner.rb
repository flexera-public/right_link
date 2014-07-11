# === Synopsis:
#   RightScale Chef recipe Runner - (c) 2009-2014 RightScale Inc
#
#   rs_run_recipe is command line tool that allows running recipes from within
#   an instance. You can also execute recipes on other instances within 
#   the deployment based upon tags.
#
# === Examples:
#   Run recipe with id 12:
#     rs_run_recipe -i 12
#     rs_run_recipe --identity 12
#
#   Run recipe 'nginx' using given JSON attributes file:
#     rs_run_recipe -n nginx -j attribs.js
#     rs_run_recipe --name nginx --json attribs.js
#
#   Run recipe 'mysql:backup' on master database
#     rs_run_recipe --name "mysql::backup" \
#       --recipient_tags "app:role=database database:master=true"
##
# === Usage:
#    rs_run_recipe --name, -n NAME [--json, -j JSON_FILE]
#                  [--recipient_tags, -r TAG_LIST]
#                  [--scope, -s SCOPE] [--verbose, -v]
#
#    Options:
#      --name, -n NAME       Chef recipe name
#      --json, -j JSON_FILE  JSON file name for JSON to be merged into
#                              attributes before running recipe
#      --thread,             Schedule the operation on a specific thread name
#        -t THREAD             for concurrent execution. Thread names must begin
#                              with a letter and can consist only of lower-case
#                              alphabetic characters, digits, and the underscore
#                              character.
#      --policy,             Audits for the executable to be run will be grouped under
#        -P POLICY             the given policy name.  All detail will be logged on 
#                              the instance, but limited detail will be audited.
#      --audit_period        Specifies the period of time that should pass between audits
#        -a PERIOD_IN_SECONDS
#      --recipient_tags,     Tags for selecting which instances are to receive
#                              request with the TAG_LIST being quoted if it
#        -r TAG_LIST           contains multiple tags. Recipe will only be executed
#                              on servers that have all the tags listed in the TAG_LIST.
#                              Target servers must be within the same deployment,
#                              or within a deployment with "global" tag scope.
#      --scope, -s SCOPE     Scope for selecting tagged recipients: single or
#                              all (default all)
#      --cfg-dir, -c DIR     Set directory containing configuration for all
#                              agents
#      --verbose, -v         Display progress information
#      --help                Display help
#      --version             Display version information
#      --timeout, -T SEC     Max time to wait for response from RightScale platform. 
#                              (default 60 sec)
#
#    Note: Partially specified option names are accepted if not ambiguous.


require File.expand_path(File.join(File.dirname(__FILE__), 'bundle_runner'))
module RightScale
  class RecipeRunner < RightScale::BundleRunner

    def initialize
      @cmd_name = 'run_recipe'
      @type     = 'recipe'
    end

    protected

    def to_forwarder_options(options)
      result = super
      result[:recipe_id] = options[:id] if options[:id]
      result[:recipe]    = options[:name] if options[:name] && !options[:id]
      result[:json]      = options[:json]
      result
    end

    # Version information
    #
    # === Return
    # (String):: Version information
    def version
      "rs_run_recipe #{right_link_version} - RightLink's Chef recipes Runner (c) 2009-2014 RightScale Inc"
    end

    def usage
      Usage.scan(__FILE__)
    end

  end
end
