require 'subconv/utility'
require 'subconv/caption'

module Subconv
  module Scc
    # Transform an array of caption grids parsed from SCC into an array of captions
    # with the caption content converted to a tree of text and style nodes
    class Transformer
      # Perform the transformation
      # Continuous text blocks are collected in each caption grid and merged
      # Empty grids will end the previously displayed caption
      def transform(captions)
        transformed_captions = []
        return [] if captions.empty?

        # Use fps from Scc
        fps = captions.first.timecode.fps
        last_time = Timecode.new(0, fps)

        captions_open = []
        captions.each do |caption|
          if caption.grid.nil? || !captions_open.empty?
            # Close any captions that might be displayed
            captions_open.each do |caption_to_close|
              caption_to_close.timespan = Utility::Timespan.new(last_time.dup, caption.timecode.dup)
            end
            transformed_captions.concat captions_open
            # All captions are closed now
            captions_open = []
          end

          unless caption.grid.nil?
            # Collect text chunks in each row and create captions out of them
            caption.grid.each_with_index do |row, row_number|
              chunks = collect_chunks(row)
              chunks.each_pair do |start_column, chunk|
                content = transform_chunk(chunk)
                position = position_from_grid(row_number, start_column)
                captions_open.push(Subconv::Caption.new(
                                     align:    :start,
                                     position: position,
                                     content:  content
                ))
              end
            end

            # Merge continuous rows?
            # captions_open.each do |caption_open|
            #
            # end
          end

          last_time = caption.timecode
        end

        unless captions_open.empty?
          # Close any captions that are still open at the end
          captions_open.each do |caption_to_close|
            caption_to_close.timespan = Utility::Timespan.new(last_time.dup, last_time + Timecode.from_seconds(5, fps))
          end
          transformed_captions.concat captions_open
        end

        transformed_captions
      end

      private

      # Properties in order of priority (first element has the highest priority)
      # The priority indicates in what order new style nodes should be created when their order
      # would be indeterminate otherwise. This is required for getting deterministic output.
      PROPERTIES = %i(color underline italics flash).freeze

      # Get the relative priority of a property
      def property_priority(property)
        # First property has the highest priority
        highest_property_priority - PROPERTIES.find_index(property)
      end

      # Get the highest possible property priority
      def highest_property_priority
        PROPERTIES.length - 1
      end

      # Map of properties to the corresponding Ruby class
      PROPERTY_CLASS_MAP = {
        color:     ColorNode,
        italics:   ItalicsNode,
        underline: UnderlineNode,
        flash:     FlashNode
      }.freeze

      # Collect all continuous character groups in a row
      # Input: Grid row as array of Scc::Character instances
      # Output: Hash with the starting column index as key and Scc::Character array as value
      def collect_chunks(row)
        chunks = {}

        collecting = false
        start_column = 0
        current_chunk = []
        row.each_with_index do |column, index|
          if collecting
            if column.nil?
              # Stop collecting, write out chunk
              collecting = false
              chunks[start_column] = current_chunk
              current_chunk = []
            else
              # Stay collecting
              current_chunk.push(column)
            end
          else
            unless column.nil?
              # Start collecting
              collecting = true
              current_chunk.push(column)
              # Remember first column
              start_column = index
            end
          end
        end

        # Write out last chunk if still open
        chunks[start_column] = current_chunk if collecting

        chunks
      end

      # Convert a grid coordinate to a relative screen position inside the video
      def position_from_grid(row, column)
        # TODO: Handle different aspect ratios
        # The following is only (presumably) true for 16:9 video
        Position.new(((column.to_f / Scc::GRID_COLUMNS) * 0.8 + 0.1) * 0.75 + 0.125, (row.to_f / Scc::GRID_ROWS) * 0.8 + 0.1)
      end

      # Transform one chunk of Scc::Character instances into text and style nodes
      # The parser goes through each character sequentially, opening and closing style nodes as necessary on the way
      def transform_chunk(chunk)
        default_style = CharacterStyle.default
        # Start out with the default style
        current_style = CharacterStyle.default
        current_text  = ''
        # Start with a stack of just the root node
        parent_node_stack = [RootNode.new]

        chunk.each_with_index do |column, column_index|
          # Gather the style properties that are different
          differences = style_differences(current_style, column.style)

          # Adjust the style by opening/closing nodes if there are any differences
          unless differences.empty?
            # Finalize currently open text node
            unless current_text.empty?
              # Insert text node into the children of the node on top of the stack
              parent_node_stack.last.children.push(TextNode.new(current_text))
              current_text = ''
            end

            # First close any nodes whose old value was different from the default value and has now changed
            differences_to_close = differences & style_differences(current_style, default_style)

            unless differences_to_close.empty?
              # Find topmost node that corresponds to any of the differences to close
              first_matching_node_index = parent_node_stack.find_index { |node|
                differences_to_close.any? { |difference| node.instance_of?(node_class_for_property(difference)) }
              }

              fail 'No node for property to close found in stack' if first_matching_node_index.nil?

              # Collect styles below it that should _not_ be closed for possible re-opening because they would otherwise get lost
              reopen = parent_node_stack[first_matching_node_index..-1].select { |node|
                !differences_to_close.any? { |difference| node.instance_of?(node_class_for_property(difference)) }
              }.map { |node| property_for_node_class(node.class) }

              # Add them to the differences (since the current style changed from what was assumed above)
              differences += reopen

              # Delete the matched node and all following nodes from the stack
              parent_node_stack.pop(parent_node_stack.length - first_matching_node_index)
            end

            # Values that are different from both the former style and the default style must result in a new node
            differences_to_open = differences & style_differences(column.style, default_style)

            # Calculate how long each style persists
            continuous_lengths = Hash[differences_to_open.map { |property|
                                        length = 1
                                        value_now = column.style.send(property)
                                        (column_index + 1...chunk.length).each do |check_column_index|
                                          break if chunk[check_column_index].style.send(property) != value_now
                                          length += 1
                                        end
                                        # Sort first by length, then by property priority
                                        [property, length * (highest_property_priority + 1) + property_priority(property)]
                                      }]
            # Sort new nodes by the length this style persists
            differences_to_open.sort_by! do |property| continuous_lengths[property] end
            differences_to_open.reverse!

            # Open new nodes
            differences_to_open.each do |property|
              value = column.style.send(property)
              new_node = node_from_property(property, value)
              # Insert into currently active parent node
              parent_node_stack.last.children.push(new_node)
              # Push onto stack
              parent_node_stack.push(new_node)
            end

            current_style = column.style
          end

          # Always add the character to the current text after adjusting the style if necessary
          current_text << column.character
        end

        # Add any leftover text
        unless current_text.empty?
          parent_node_stack.last.children.push(TextNode.new(current_text))
        end
        # Return the root node
        parent_node_stack.first
      end

      # Get the Ruby class for a given property (symbol)
      def node_class_for_property(property)
        PROPERTY_CLASS_MAP.fetch(property)
      end

      # Get the property (symbol) for a given Ruby class
      def property_for_node_class(node_class)
        PROPERTY_CLASS_MAP.invert.fetch(node_class)
      end

      # Create a Ruby node instance from a given property (symbol) and the property value
      def node_from_property(property, value)
        property_class = node_class_for_property(property)
        if property_class == ColorNode
          ColorNode.new(value.to_symbol)
        else
          fail 'Cannot create boolean property node for property off' unless value
          property_class.new
        end
      end

      # Determine all properties (as array of symbols) that are different between the
      # Scc::CharacterStyle instances a and b
      def style_differences(a, b)
        PROPERTIES.select { |property|
          value_a = a.send(property)
          value_b = b.send(property)

          value_a != value_b
        }
      end
    end
  end
end
