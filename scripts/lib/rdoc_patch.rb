# Patch RDoc so that RDoc::usage works even when the application is started via
# a proxy such as a bash script instead of being run directly.
# See resat.rb for usage information.
#

module RDoc
  # Force the use of comments in this file so RDoc::usage works even when
  # invoked from a proxy (e.g. 'resat' bash script)
  def usage_no_exit(*args)
    main_program_file = caller[-1].sub(/:\d+$/, '')
    usage_from_file(main_program_file)
  end

  # Display usage from the given file
  def RDoc.usage_from_file(input_file, *args)
    comment = File.open(input_file) do |file|
      find_comment(file)
    end
    comment = comment.gsub(/^\s*#/, '')
    markup = SM::SimpleMarkup.new
    flow_convertor = SM::ToFlow.new
    flow = markup.convert(comment, flow_convertor)
    format = "plain"
    unless args.empty?
      flow = extract_sections(flow, args)
    end
    options = RI::Options.instance
    if args = ENV["RI"]
      options.parse(args.split)
    end
    formatter = options.formatter.new(options, "")
    formatter.display_flow(flow)
  end
end

