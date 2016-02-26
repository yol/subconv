# frozen_string_literal: true
require 'subconv/utility'

require 'solid_struct'
require 'timecode'

module Subconv
  module Scc
    FILE_MAGIC = 'Scenarist_SCC V1.0'.freeze

    # Grid size
    GRID_ROWS = 15
    GRID_COLUMNS = 32

    # Grid is just an array with some extra convenience functions and a default size
    class Grid < Array
      def initialize
        super(GRID_ROWS) { Array.new(GRID_COLUMNS) }
      end

      # The grid is empty when there are no characters in it
      def empty?
        flatten.compact.empty?
      end

      # Insert continuous text at a given position
      # Returns self for chaining
      def insert_text(row, column, text, style = CharacterStyle.default)
        text.each_char do |char|
          self[row][column] = Character.new(char, style)
          column += 1
        end
        self
      end
    end

    # Color constants as immutable value objects with some convenience functions (e.g. conversion to string or symbol)
    # All available colors are registered as constants in this class, e.g. Color::WHITE, Color::RED and so on
    # The instances of this class are all frozen and can never be changed.
    # Instances can be retrieved only by the constants or with ::for_value
    class Color
      def initialize(color)
        @color = color
      end

      # CEA-608 color code
      def value
        @color
      end
      alias to_i value

      # Lower-case CEA-608 name of the color
      def to_s
        to_symbol.to_s
      end
      alias inspect to_s

      # rubocop:disable MutableConstant
      COLORS = {}
      TO_SYMBOL_MAP = {}
      # rubocop:enable MutableConstant

      def self.register_color(name, value)
        # Make sure the new color is immutable
        new_color = Color.new(value).freeze
        # Register in lookup tables
        COLORS[value] = new_color
        TO_SYMBOL_MAP[value] = name
        # Register as class constant
        const_set(name.to_s.upcase, new_color)
      end

      # CEA-608 colors
      register_color :white, 0
      register_color :green, 1
      register_color :blue, 2
      register_color :cyan, 3
      register_color :red, 4
      register_color :yellow, 5
      register_color :magenta, 6

      # Prevent future modifications
      COLORS.freeze
      TO_SYMBOL_MAP.freeze

      # Lower-case CEA608 name of the color as symbol
      def to_symbol
        TO_SYMBOL_MAP[@color]
      end

      # Get the Color instance corresponding to a CEA608 color code
      def self.for_value(value)
        color = COLORS[value]
        raise "Color value #{value} is unknown" if color.nil?
        color
      end

      # Disallow creating new instances
      private_class_method :new
    end

    # Encapsulates properties of single characters
    CharacterStyle = SolidStruct.new(:color, :italics, :underline, :flash)
    class << CharacterStyle
      def default
        CharacterStyle.new(color: Color::WHITE, italics: false, underline: false, flash: false)
      end
    end

    # One character in the closed caption grid
    Character = SolidStruct.new(:character, :style)

    # One fully rendered caption displayed at a specific point in time
    Caption = SolidStruct.new(:timecode, :grid)

    # SCC reader
    # Parse and render an SCC file sequentially into a background and foreground grid
    # like a TV set would do and store the resulting closed captions as grid snapshots into an array
    # whenever the foreground grid changes.
    #
    # Only captions in data channel 1 are read. Also, invalid byte parity will raise an error unless checking is disabled.
    # The advanced recovery methods mentioned in CEA608 are not implemented since the source is assumed to contain no errors (e.g. DVD source).
    class Reader
      # Regular expression for parsing one line of data
      LINE_REGEXP = /^(?<timecode>[0-9:;]+)\t(?<data>(?:[0-9a-fA-F]{4} ?)+)$/

      # rubocop:disable MutableConstant

      # Map of standard characters that do not match the standard ASCII codes
      # to their corresponding unicode characters
      STANDARD_CHARACTER_MAP = {
        '*'    => "\u00e1",
        '\\'   => "\u00e9",
        '^'    =>	"\u00ed",
        '_'    =>	"\u00f3",
        '`'    =>	"\u00fa",
        '{'    =>	"\u00e7",
        '|'    =>	"\u00f7",
        '}'    =>	"\u00d1",
        '~'    =>	"\u00f1",
        "\x7f" =>	"\u2588"
      }
      # rubocop:enable MutableConstant
      # Simply return the character if no exception matched
      STANDARD_CHARACTER_MAP.default_proc = proc do |_hash, key|
        key
      end
      STANDARD_CHARACTER_MAP.freeze

      # Map of special characters to unicode codepoints
      SPECIAL_CHARACTER_MAP = {
        '0' => "\u00ae",
        '1' => "\u00b0",
        '2' => "\u00bd",
        '3' => "\u00bf",
        '4' => "\u2122",
        '5' => "\u00a2",
        '6' => "\u00a3",
        '7' => "\u266a",
        '8' => "\u00e0",
        # "\x39" => 	transparent space is handled specially since it is not a real character
        ':' => "\u00e8",
        ';' => "\u00e2",
        '<' => "\u00ea",
        '=' => "\u00ee",
        '>' => "\u00f4",
        '?' => "\u00fb"
      }.freeze

      # Map of preamble address code high bytes to their
      # corresponding base row numbers (counted from 0)
      PREAMBLE_ADDRESS_CODE_ROW_MAP = {
        0x10 => 10,
        0x11 => 0,
        0x12 => 2,
        0x13 => 11,
        0x14 => 13,
        0x15 => 4,
        0x16 => 6,
        0x17 => 8
      }.freeze

      # Error classes
      class Error < RuntimeError; end
      class InvalidFormatError < Error; end
      class ParityError < Error; end

      # Internal state of the parser consisting of current drawing position and character style
      class State
        def initialize(params)
          self.row = params[:row]
          self.column = params[:column]
          @style = params[:style]
        end

        attr_accessor :style
        attr_reader :row, :column

        # Make sure the maximum row count is not exceeded
        def row=(row)
          @row = Utility.clamp(row, 0, GRID_ROWS - 1)
        end

        # Make sure the cursor does not get outside the screen left or right
        def column=(column)
          @column = Utility.clamp(column, 0, GRID_COLUMNS - 1)
        end

        def self.default
          State.new(row: 0, column: 0, style: CharacterStyle.default)
        end
      end

      # Actual conversion result
      attr_reader :captions

      # Read an SCC file from the IO object io for a video
      def read(io, fps, check_parity = true)
        # Initialize new grids for character storage
        @foreground_grid = Grid.new
        @background_grid = Grid.new
        # Initialize state
        @state = State.default
        @captions = []
        @now = Timecode.new(0, fps)
        @data_channel = 0

        magic = io.readline.chomp!
        raise InvalidFormatError, 'File does not start with "' + Scc::FILE_MAGIC + '"' unless Scc::FILE_MAGIC == magic

        io.each_line do |line|
          line.chomp!
          # Skip empty lines between the commands
          next if line.empty?

          line_data = LINE_REGEXP.match(line)
          raise InvalidFormatError, "Invalid line \"#{line}\"" if line_data.nil?
          # Parse timecode
          old_time = @now
          timecode = Timecode.new(line_data[:timecode], fps)
          @now = timecode
          raise InvalidFormatError, 'New timecode is behind last time' if @now < old_time

          # Parse data words
          parse_data(line_data[:data], check_parity)
        end
      end

      private

      # Parse one line of SCC data
      def parse_data(data, check_parity)
        last_command = [0, 0]

        data.split(' ').each do |word_string|
          begin
            # Decode hexadecimal word into two-byte string
            word = [word_string].pack('H*')
            # Check parity
            raise ParityError, "At least one byte in word #{word_string} has even parity, odd required" unless !check_parity || (correct_parity?(word[0]) && correct_parity?(word[1]))
            # Remove parity bit for further processing
            word = word.bytes.collect { |byte|
              # Unset 8th bit
              (byte & ~(1 << 7))
            }

            hi, lo = word

            # First check if the word contains characters only
            if hi >= 0x20 && hi <= 0x7f
              # Skip characters if last command was on different channel
              if @data_channel != 0
                puts 'Skipping characters on channel 2'
                next
              end

              [hi, lo].each do |byte|
                handle_character(byte)
              end

              # Reset last command
              last_command = [0, 0]
            else
              if word == last_command
                # Skip commands transmitted twice for redundancy
                # But don't skip the next time, too
                last_command = [0, 0]
                next
              end

              # Channel information is encoded in the 4th bit, read it out
              @data_channel = (hi >> 3) & 1
              if @data_channel != 0
                puts 'Skipping command on channel 2'
                next
                # If channel 2 processing is needed, parse the file two times and
                # change the above condition as needed, then unset the channel bit
                # for further processing.
              end

              if hi == 0x11 && lo >= 0x30 && lo <= 0x3f
                # Special character
                handle_special_character(lo)
              elsif hi >= 0x10 && hi <= 0x17 && lo >= 0x40
                # Premable address code
                handle_preamble_address_code(hi, lo)
              elsif (hi == 0x14 || hi == 0x17) && lo >= 0x20 && lo <= 0x2f
                handle_control_code(hi, lo)
              elsif hi == 0x11 && lo >= 0x20 && lo <= 0x2f
                handle_mid_row_code(hi, lo)
              elsif hi == 0x00 && lo == 0x00
                # Ignore filler
              else
                puts "Ignoring unknown command #{hi}/#{lo}"
              end

              last_command = word
            end

          ensure
            # Advance one frame for each word read
            @now += 1
          end
        end
      end

      # Insert one unicode character into the grid at the current position and with the
      # current style, then advance the cursor one column
      def insert_character(char)
        @background_grid[@state.row][@state.column] = Character.new(char, @state.style.dup)
        @state.column += 1
      end

      # Insert a CEA608 character into the grid at the current position, converting it to its unicode representation
      def handle_character(byte)
        # Ignore filler character
        return if byte == 0

        char = STANDARD_CHARACTER_MAP[byte.chr]
        insert_character(char)
      end

      # Insert a special character into the grid at the current position, or delete the current column
      # in case of a transparent space.
      def handle_special_character(byte)
        if byte == 0x39
          # Transparent space: Move cursor after deleting the current column to open up a hole
          @background_grid[@state.row][@state.column] = nil
          @state.column += 1
        else
          char = SPECIAL_CHARACTER_MAP[byte.chr]
          insert_character(char)
        end
      end

      # Set drawing position and style according to the information in a preamble address code
      def handle_preamble_address_code(hi, lo)
        @state.row = PREAMBLE_ADDRESS_CODE_ROW_MAP[hi]
        # Low byte bit 5 adds 1 to the row number if set
        @state.row += 1 if lo & (1 << 5) != 0

        # Low byte bit 0 indicates whether underlining is to be enabled
        @state.style.underline = ((lo & 1) == 1)
        # Low byte bit 4 indicates whether it is an indent or a formatting code
        is_indent = (((lo >> 4) & 1) == 1)
        # Low byte bits 1 to 3 are the color or indent code, depending on is_indent
        color_or_indent = (lo >> 1) & 0x7

        # Reset style
        @state.style.flash = false
        @state.style.italics = false

        if is_indent
          # Indent code always sets white as color attribute
          @state.style.color = Color::WHITE
          # One indent equals 4 characters
          @state.column = color_or_indent * 4
        elsif color_or_indent == 7
          # "color" 7 is white with italics
          @state.style.color = Color::WHITE
          @state.style.italics = true
        else
          @state.style.color = Color.for_value(color_or_indent)
        end
      end

      # Process a miscellaneous control code
      def handle_control_code(hi, lo)
        if hi == 0x14 && lo == 0x20
          # Resume caption loading
          # Nothing to do here, only pop-onstyle is supported anyway
        elsif hi == 0x14 && lo == 0x21
          # Backspace
          unless @state.column.zero? # Ignore in the first column
            @state.column -= 1
            # Delete character at cursor after moving one character back
            @background_grid[@state.row][@state.column] = nil
          end
        elsif hi == 0x14 && lo == 0x24
          # Delete to end of row
          (@state.column...GRID_COLUMNS).each do |column|
            @background_grid[@state.row][column] = nil
          end
        elsif hi == 0x14 && lo == 0x28
          # Flash on
          # Flash is a spacing character
          insert_character(' ')
          @state.style.flash = true
          # elsif hi == 0x14 && lo == 0x2b
          # Resume text display -> not a pop-on command
          # fail "RTD"
        elsif hi == 0x14 && lo == 0x2c
          # Erase displayed memory
          @foreground_grid = Grid.new
          post_frame
        elsif hi == 0x14 && lo == 0x2e
          # Erase non-displayed memory
          @background_grid = Grid.new
        elsif hi == 0x14 && lo == 0x2f
          # End of caption (flip memories)
          @foreground_grid, @background_grid = @background_grid, @foreground_grid
          post_frame
        elsif hi == 0x17 && lo >= 0x21 && lo <= 0x23
          # Tab offset
          # Bits 0 and 1 designate how many columns to go
          @state.column += (lo & 0x3)
        else
          puts "Ignoring unknown control code #{hi}/#{lo}"
        end
      end

      # Process a mid-row code
      def handle_mid_row_code(_hi, lo)
        # Mid-row codes are spacing characters
        insert_character(' ')
        # Low byte bit 0 indicates whether underlining is to be enabled
        @state.style.underline = ((lo & 1) == 1)
        # Low byte bits 1 to 3 are the color code
        color = (lo >> 1) & 0x7

        if color == 0x7
          @state.style.italics = true
        else
          # Color mid-row codes disable italics
          @state.style.italics = false
          @state.style.color = Color.for_value(color)
        end
        # All mid-row codes always disable flash
        @state.style.flash = false
      end

      # Insert the currently displayed foreground grid as caption into the captions array
      # Must be called whenever the foreground grid is changed as a result of a command
      def post_frame
        # Only push a new caption if the grid has changed
        if @captions.empty? || @foreground_grid != @last_grid
          # Save space by not saving the grid if it is completely empty
          grid = @foreground_grid.empty? ? nil : @foreground_grid
          @captions.push(Caption.new(timecode: @now, grid: grid))
          @last_grid = @foreground_grid
        end
      end

      # Check a byte for odd parity
      def correct_parity?(byte)
        byte.ord.to_s(2).count('1').odd?
      end
    end
  end
end
