# frozen_string_literal: true
require 'subconv/utility'
require 'subconv/caption'

module Subconv
  module WebVtt
    FILE_MAGIC = 'WEBVTT'.freeze

    TIMECODE_FORMAT = '%02d:%02d:%02d.%03d'.freeze
    CUE_FORMAT = '%{start_time} --> %{end_time} %{settings}'.freeze

    # WebVTT caption writer
    class Writer
      def initialize(options = {})
        @options = options
      end

      # Write captions to an IO stream
      # captions must be an array of Caption instances
      def write(io, captions)
        io.write(FILE_MAGIC + "\n\n")

        captions.each do |caption|
          write_caption(io, caption)
        end
      end

      # Write a single Scc::Caption to an IO stream
      def write_caption(io, caption)
        settings = {
          'align' => caption.align.to_s
        }
        if caption.position.is_a?(Position)
          settings['line'] = webvtt_percentage(caption.position.y)
          settings['position'] = webvtt_percentage(caption.position.x)
        else
          settings['line'] = case caption.position
                             when :top
                               # '0' would be better here, but Chrome does not support that yet
                               '5%'
                             when :bottom
                               '-1,end'
                             else
                               raise "Unknown position #{caption.position}"
                             end
        end

        # Remove align if it is the default value anyway
        settings.delete('align') if settings['align'] == 'middle'

        # Convert settings to string representation
        settings_string = settings.map { |setting|
          setting.join(':')
        }.join(' ')

        io.write(CUE_FORMAT % {
          start_time: timecode_to_webvtt(caption.timespan.start_time),
          end_time:   timecode_to_webvtt(caption.timespan.end_time),
          settings:   settings_string
        } + "\n")
        text = node_to_webvtt_markup caption.content
        if @options[:trim_line_whitespace]
          # Trim leading and trailing whitespace from each line
          text = text.split("\n").each(&:strip!).join("\n")
        end
        io.write "#{text}\n\n"
      end

      private

      # Format a value between 0 and 1 as percentage with 3 digits behind the decimal point
      def webvtt_percentage(value)
        format('%.3f%%', (value * 100.0))
      end

      # Convert a timecode to the h/m/s format required by WebVTT
      def timecode_to_webvtt(time)
        value = time.to_seconds

        milliseconds = ((value * 1000) % 1000).to_i
        seconds      =  value.to_i % 60
        minutes      = (value.to_i / 60) % 60
        hours        =  value.to_i / 60 / 60

        format(TIMECODE_FORMAT, hours, minutes, seconds, milliseconds)
      end

      # Replace WebVTT special characters in the text
      def escape_text(text)
        text = text.dup
        text.gsub!('&', '&amp;')
        text.gsub!('<', '&lt;')
        text.gsub!('>', '&rt;')
        text
      end

      # Convert an array of nodes to their corresponding WebVT markup
      def nodes_to_webvtt_markup(nodes)
        nodes.map { |node| node_to_webvtt_markup(node) }.join
      end

      # Convert one node to its corresponding WebVTT markup
      # Conversion is very straightforward. Container nodes are converted recursively by calling
      # nodes_to_webvtt_markup from within this function. Recursion depth should not be a problem
      # since their are not that many different properties.
      def node_to_webvtt_markup(node)
        # Text nodes just need to have their text converted
        return escape_text(node.text) if node.instance_of?(TextNode)

        # If it is not a text node, it must have children
        children = nodes_to_webvtt_markup(node.children)

        # Use an array because the === operator of Class does not work as expected (Array === Array is false)
        case [node.class]
        when [RootNode]
          children
        when [ItalicsNode]
          '<i>' + children + '</i>'
        when [UnderlineNode]
          '<u>' + children + '</u>'
        when [FlashNode]
          '<c.blink>' + children + '</c>'
        when [ColorNode]
          '<c.' + node.color.to_s + '>' + children + '</c>'
        else
          raise "Unknown node class #{node.class}"
        end
      end
    end
  end
end
