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

