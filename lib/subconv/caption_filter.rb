require 'subconv/caption'

module Subconv
  # Apply post-processing to captions
  # Supported operations:
  # - remove color nodes
  # - remove flash nodes
  # - convert XY viewport relative positions to simple top or bottom positions
  # - merge multiple captions on screen at the same time into one caption
  class CaptionFilter
    def initialize(options)
      @options = options
      @options[:filter_node_types] ||= []
      @options[:filter_node_types].push ColorNode if @options[:remove_color]
      @options[:filter_node_types].push FlashNode if @options[:remove_flash]
    end

    def process!(captions)
      last_timespan = nil
      open_captions = {}
      last_top_position = nil

      captions.map! do |caption|
        is_same_timespan = last_timespan == caption.timespan

        unless is_same_timespan
          # Time changed -> do not compare with previous top position
          last_top_position = nil
          open_captions = {}
        end

        if @options[:xy_position_to_top_or_bottom]
          caption.position = if caption.position.y < 0.5
                               last_top_position = caption.position.y
                               :top
                             elsif !last_top_position.nil? && (caption.position.y - last_top_position) < 0.08
                               # Do not move lines to the bottom when they are continuing directly
                               # from a caption displayed at the top to avoid continuous captions
                               # being thorn in half
                               last_top_position = caption.position.y
                               :top
                             else
                               :bottom
                             end

          # x position is removed altogether and the caption is now center-aligned
          caption.align = :middle
        end

        # Captions are expected to be ordered by increasing timespan and y position (this is
        # guaranteed for the SCC reader)
        if @options[:merge_by_position] && is_same_timespan && open_captions.key?(caption.position)
          target_caption = open_captions[caption.position]
          target_caption.content.children.push TextNode.new("\n")
          target_caption.content.children.concat caption.content.children
          # Remove this caption since it has been merged
          next
        end

        last_timespan = caption.timespan

        open_captions[caption.position] = caption
        caption
      end
      # Remove nils resulting from removed captions
      captions.compact!
      # Do per-caption processing after merging etc.
      captions.each do |caption|
        process_caption!(caption)
      end
    end

    def process_caption!(caption)
      filter_nodes! caption.content
      merge_text_nodes! caption.content
    end

    private

    # Merge continuous text nodes
    # Example: [TextNode("a"), TextNode("b")] -> [TextNode("ab")]
    def merge_text_nodes!(node)
      return node unless node.is_a? ContainerNode

      current_text_node = nil
      node.children.map! do |child|
        if child.is_a? TextNode
          if current_text_node.nil?
            current_text_node = child
          else
            # Add text to previous node
            current_text_node.text << child.text
            # Remove this node
            next
          end
        else
          current_text_node = nil
          merge_text_nodes! child
        end
        child
      end

      # Remove nils from removed text nodes
      node.children.compact!
    end

    # Remove specified nodes in an array, i.e. replace them with their children
    # Only container nodes can be filtered
    def filter_nodes!(node)
      return node unless node.is_a? ContainerNode

      node.children.map! do |child|
        # Filter recursively
        filter_nodes! child
        if @options[:filter_node_types].include?(child.class)
          # Replace child with contents
          child.children
        else
          child
        end
      end
      # Flatten away arrays that might have been introduced
      # by removing nodes
      node.children.flatten!

      node
    end
  end
end
