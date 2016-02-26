module Subconv
  module Utility
    class InvalidTimespanError < RuntimeError; end

    class Timespan
      def initialize(start_time, end_time)
        @start_time = start_time
        @end_time = end_time
        raise InvalidTimespanError, 'Timespan end time is before start time' if @end_time < @start_time
        raise InvalidTimespanError, 'Timespan is empty' if @start_time == @end_time
      end

      def ==(other)
        self.class == other.class && @start_time == other.start_time && @end_time == other.end_time
      end

      attr_reader :start_time, :end_time
    end

    def self.clamp(value, min, max)
      return min if value < min
      return max if value > max
      value
    end

    def self.node_to_tree_string(node, level = 0)
      node_text = node.class.to_s
      if node.is_a?(TextNode)
        node_text << " \"#{node.text}\""
      elsif node.is_a?(ColorNode)
        node_text << " #{node.color}"
      end
      result = "\t" * level + node_text + "\n"
      if node.is_a?(ContainerNode)
        node.children.each { |child|
          result << node_to_tree_string(child, level + 1)
        }
      end
      result
    end
  end
end
