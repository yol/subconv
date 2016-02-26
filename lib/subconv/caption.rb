module Subconv
  # Two-dimensional screen position relative (both x and y position between 0 and 1) to the screen size
  class Position
    def initialize(x, y)
      self.x = x
      self.y = y
    end

    def ==(other)
      # Ignore small differences in the position
      self.class == other.class && (@x - other.x).abs < 0.01 && (@y - other.y).abs < 0.01
    end

    attr_reader :x, :y

    # Force x position to be a float between 0 and 1
    def x=(x)
      x = x.to_f
      raise RangeError, 'X position not between 0 and 1' unless x.between?(0.0, 1.0)
      @x = x
    end

    # Force y position to be a float between 0 and 1
    def y=(y)
      y = y.to_f
      raise RangeError, 'Y position not between 0 and 1' unless y.between?(0.0, 1.0)
      @y = y
    end
  end

  # Base class for all nodes
  class CaptionNode; end

  # Node that contains text
  class TextNode < CaptionNode
    def initialize(text)
      @text = text
    end

    def ==(other)
      self.class == other.class && @text == other.text
    end

    attr_accessor :text
  end

  # Node that contains other nodes
  class ContainerNode < CaptionNode
    def initialize(children = [])
      self.children = children
    end

    def ==(other)
      self.class == other.class && @children == other.children
    end

    attr_reader :children

    def children=(children)
      raise 'Children must be an array' unless children.class == Array
      @children = children
    end
  end

  # Special node used as root element for all content
  class RootNode < ContainerNode; end

  # Italics style node
  class ItalicsNode < ContainerNode; end
  # Underline style node
  class UnderlineNode < ContainerNode; end
  # Flash style node
  class FlashNode < ContainerNode; end
  # Color style node
  class ColorNode < ContainerNode
    # Color should be given as symbol, e.g. :white, :red, :blue, ...
    def initialize(color, children = [])
      super children
      @color = color
    end

    def ==(other)
      super(other) && @color == other.color
    end

    attr_accessor :color
  end

  # Caption displayed on the screen at a specific position for a given amount of time
  class Caption
    def initialize(params)
      # :start, :middle or :end
      @align = params[:align]
      @timespan = params[:timespan]
      # Position instance, :top or :bottom
      @position = params[:position]
      @content = params[:content]
    end

    def ==(other)
      self.class == other.class && @timespan == other.timespan && @position == other.position && @content == other.content
    end

    attr_accessor :timespan, :position, :align, :content
  end
end
