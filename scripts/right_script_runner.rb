# === Synopsis:
#   RightScale RightScript Runner - (c) 2009-2014 RightScale Inc
#
#   rs_run_right_script is command line tool that allow
#   running RightScripts from within an instance
#
# === Examples:
#   Run RightScript with id 14 and override input 'APPLICATION' with value
#   'Mephisto':
#     rs_run_right_script -i 14 -p APPLICATION=text:Mephisto
#     rs_run_right_script --identity 14 --parameter APPLICATION=text:Mephisto
#
# === Usage:
#    rs_run_right_script --identity, -i ID [--parameter, -p NAME=type:VALUE]*
#                  [--verbose, -v]
#    rs_run_right_script --name, -n NAME [--parameter, -p NAME=type:VALUE]*
#                  [--recipient_tags, -r TAG_LIST]
#                  [--scope, -s SCOPE] [--verbose, -v]
#
#      * Can appear multiple times
#
#    Options:
#      --identity, -i ID     RightScript id
#      --name, -n NAME       RightScript name (overridden by id)
#      --parameter,
#        -p NAME=TYPE:VALUE  Define or override RightScript input
#                              Note: Only applies to run_right_script
#      --thread,             Schedule the operation on a specific thread name
#        -t THREAD             for concurrent execution. Thread names must begin
#                              with a letter and can consist only of lower-case
#                              alphabetic characters, digits, and the underscore
#                              character.
#      --policy,              Audits for the executable to be run will be grouped under
#        -P POLICY             the given policy name.  All detail will be logged on the instance,
#                              but limited detail will be audited.
#      --audit_period        Specifies the period of time that should pass between audits
#        -a PERIOD_IN_SECONDS
#      --recipient_tags,     Tags for selecting which instances are to receive
#                              request with the TAG_LIST being quoted if it
#        -r TAG_LIST           contains spaces. Script will only be executed
#                              on servers that have all the tags listed in the TAG_LIST
#      --scope, -s SCOPE     Scope for selecting tagged recipients: single or
#                              all (default all)
#      --cfg-dir, -c DIR     Set directory containing configuration for all
#                              agents
#      --verbose, -v         Display progress information
#      --help:               Display help
#      --version:            Display version information
#      --timeout, -T SEC     Custom timeout (default 60 sec)
#
#    Note: Partially specified option names are accepted if not ambiguous.


require File.expand_path(File.join(File.dirname(__FILE__), 'bundle_runner'))
module RightScale
  class RightScriptRunner < RightScale::BundleRunner

    def initialize
      @cmd_name = 'run_right_script'
      @type     = 'RightScript'
    end

    protected

    def to_forwarder_options(options)
      result = super
      result[:right_script_id] = options[:id] if options[:id]
      result[:right_script]    = options[:name] if options[:name] && !options[:id]
      result[:arguments]       = options[:parameters] unless options[:parameters].empty?
      result
    end

    # Version information
    #
    # === Return
    # (String):: Version information
    def version
      "rs_run_right_script #{right_link_version} - RightLink's RightScripts Runner (c) 2014 RightScale Inc"
    end

    def usage
      Usage.scan(__FILE__)
    end

  end
end
