require 'subconv/scc/reader'
require 'test_helpers'

module Subconv
  # Often used codes:
  # 9420: Resume caption loading
  # 91d0: Preamble address code for row 0 column 0
  # 942f: End of caption
  describe Scc::Reader do
    include TestHelpers

    let(:backspace) { '94a1 94a1' }
    let(:test) { '54e5 73f4' }
    let(:a) { 'c180' }

    before(:each) do
      @reader = Scc::Reader.new
    end

    it 'should reject garbage' do
      expect {
        @reader.read(StringIO.new('safjewofjpoajfljg'), default_fps)
      }.to raise_error(Scc::Reader::InvalidFormatError)
    end

    # Helper function to create a string that represents an SCC file with
    # a single caption at zero time
    # data must be given as fully formatted SCC string
    def caption_at_zero(data)
      "Scenarist_SCC V1.0\n\n00:00:00:00\t#{data}"
    end

    # Parse the input string with Scc::Reader and return the resulting captions
    def get_captions(input, fps = default_fps, check_parity = true)
      @reader.read(StringIO.new(input), fps, check_parity)
      @reader.captions
    end

    it 'should reject data with wrong parity' do
      expect {
        get_captions(caption_at_zero("9420 11d0 #{test} 942f"))
      }.to raise_error(Scc::Reader::ParityError)
    end

    it 'should decode simple text' do
      expected_grid = Scc::Grid.new.insert_text(0, 0, 'Test')

      expect(get_captions(caption_at_zero("9420 91d0 #{test} 942f"))).to eq([Scc::Caption.new(timecode: Timecode.new(4, default_fps), grid: expected_grid)])
    end

    it 'should not reject data with wrong parity when checking is not requested' do
      expected_grid = Scc::Grid.new.insert_text(0, 0, 'Test')

      expect(get_captions(caption_at_zero("9420 11d0 #{test} 942f"), default_fps, false)).to eq([Scc::Caption.new(timecode: Timecode.new(4, default_fps), grid: expected_grid)])
    end

    expected_rows = {
      '9140' => 0,
      '91E0' => 1,
      '9240' => 2,
      '92E0' => 3,
      '1540' => 4,
      '15E0' => 5,
      '1640' => 6,
      '16E0' => 7,
      '9740' => 8,
      '97E0' => 9,
      '1040' => 10,
      '1340' => 11,
      '13E0' => 12,
      '9440' => 13,
      '94E0' => 14
    }

    expected_rows.each_pair do |pac, row|
      it "should decode the preamble address code #{pac} to row #{row}" do
        expected_grid = Scc::Grid.new.insert_text(row, 0, 'Test')
        expect(get_captions(caption_at_zero("9420 #{pac} #{test} 942f"))).to eq([Scc::Caption.new(timecode: Timecode.new(4, default_fps), grid: expected_grid)])
      end
    end

    expected_column = {
      '91d0' => 0,
      '9152' => 4,
      '9154' => 8,
      '91D6' => 12,
      '9158' => 16,
      '91da' => 20,
      '91dc' => 24,
      '915e' => 28
    }

    expected_column.each_pair do |pac, column|
      it "should decode the preamble address code #{pac} to column #{column}" do
        expected_grid = Scc::Grid.new.insert_text(0, column, 'Test')
        expect(get_captions(caption_at_zero("9420 #{pac} #{test} 942f"))).to eq([Scc::Caption.new(timecode: Timecode.new(4, default_fps), grid: expected_grid)])
      end
    end

    it 'should handle backspace' do
      expected_grid = Scc::Grid.new.insert_text(1, 0, 'Test')
      # Write AA, then backspace three times, go to next row, write Tesu, backspace one time, then write t
      # -> Should result in the first line being empty and the second line reading "Test"
      expect(get_captions(caption_at_zero('9420 91d0 c1c1 ' + (backspace + ' ') * 3 + "91e0 54e5 7375 #{backspace} f480 942f"))).to eq([Scc::Caption.new(timecode: Timecode.new(15, default_fps), grid: expected_grid)])
    end

    it 'should handle overflowing lines' do
      expected_grid = Scc::Grid.new.insert_text(0, 0, 'A' * 31 + 'B')
      # Write 40 As and then tw Bs
      # -> Should result in 31 As and one B since after overflow the last column is overwritten the whole time
      expect(get_captions(caption_at_zero('9420 91d0 ' + ('c1c1 ' * 20) + 'c2c2 942f'))).to eq([Scc::Caption.new(timecode: Timecode.new(23, default_fps), grid: expected_grid)])
    end

    it 'should handle italics' do
      style = Scc::CharacterStyle.default
      style.italics = true
      # Italics is a mid-row spacing code, so expect a space before the text
      expected_grid = Scc::Grid.new.insert_text(0, 0, ' ').insert_text(0, 1, 'Test', style)
      expect(get_captions(caption_at_zero("9420 91d0 91ae #{test} 942f"))).to eq([Scc::Caption.new(timecode: Timecode.new(5, default_fps), grid: expected_grid)])
    end

    it 'should turn off flash on italics mid-row codes' do
      style = Scc::CharacterStyle.default
      flash_style = Scc::CharacterStyle.default
      style.italics = true
      flash_style.flash = true
      # Two spaces before the text
      expected_grid = Scc::Grid.new.insert_text(0, 0, ' ').insert_text(0, 1, ' ', flash_style).insert_text(0, 2, 'Test', style)
      # "<flash on><italics>Test"
      expect(get_captions(caption_at_zero("9420 91d0 94a8 91ae #{test} 942f"))).to eq([Scc::Caption.new(timecode: Timecode.new(6, default_fps), grid: expected_grid)])
    end

    it 'should handle italics preamble address code' do
      style = Scc::CharacterStyle.default
      style.italics = true
      expected_grid = Scc::Grid.new.insert_text(0, 0, 'Test', style)
      expect(get_captions(caption_at_zero("9420 91ce #{test} 942f"))).to eq([Scc::Caption.new(timecode: Timecode.new(4, default_fps), grid: expected_grid)])
    end

    it 'should handle italics and underline preamble address code' do
      style = Scc::CharacterStyle.default
      style.italics = true
      style.underline = true
      expected_grid = Scc::Grid.new.insert_text(0, 0, 'Test', style)
      expect(get_captions(caption_at_zero("9420 914f #{test} 942f"))).to eq([Scc::Caption.new(timecode: Timecode.new(4, default_fps), grid: expected_grid)])
    end

    it 'should handle underline' do
      style = Scc::CharacterStyle.default
      style.underline = true
      # Underline is a mid-row spacing code, so expect a space before the text
      expected_grid = Scc::Grid.new.insert_text(0, 0, ' ').insert_text(0, 1, 'Test', style)
      expect(get_captions(caption_at_zero("9420 91d0 91a1 #{test} 942f"))).to eq([Scc::Caption.new(timecode: Timecode.new(5, default_fps), grid: expected_grid)])
    end

    it 'should handle italics and underline' do
      style = Scc::CharacterStyle.default
      style.italics = true
      style.underline = true
      # Italics/underline is a mid-row spacing code, so expect a space before the text
      expected_grid = Scc::Grid.new.insert_text(0, 0, ' ').insert_text(0, 1, 'Test', style)
      expect(get_captions(caption_at_zero("9420 91d0 912f #{test} 942f"))).to eq([Scc::Caption.new(timecode: Timecode.new(5, default_fps), grid: expected_grid)])
    end

    color_code_map = {
      Scc::Color::WHITE   => '9120',
      Scc::Color::GREEN   => '91a2',
      Scc::Color::BLUE    => '91a4',
      Scc::Color::CYAN    => '9126',
      Scc::Color::RED     => '91a8',
      Scc::Color::YELLOW  => '912a',
      Scc::Color::MAGENTA => '912c'
    }

    color_code_map.each_pair do |color, color_code|
      it "should handle the color #{color}" do
        style = Scc::CharacterStyle.default
        style.color = color
        expected_grid = Scc::Grid.new.insert_text(0, 0, 'A', style)
        expect(get_captions(caption_at_zero("9420 91d0 #{color_code} #{backspace} #{a} 942f"))).to eq([Scc::Caption.new(timecode: Timecode.new(6, default_fps), grid: expected_grid)])
      end
    end

    it 'should turn off italics on color' do
      style = Scc::CharacterStyle.default
      italics_style = Scc::CharacterStyle.default
      style.color = Scc::Color::RED
      italics_style.italics = true
      # Two spaces before the text
      expected_grid = Scc::Grid.new.insert_text(0, 0, ' ').insert_text(0, 1, ' ', italics_style).insert_text(0, 2, 'Test', style)
      # "<italics><red>Test"
      expect(get_captions(caption_at_zero("9420 91d0 91ae 91a8 #{test} 942f"))).to eq([Scc::Caption.new(timecode: Timecode.new(6, default_fps), grid: expected_grid)])
    end

    it 'should handle all available attributes combined' do
      style = Scc::CharacterStyle.default
      style.color = Scc::Color::RED
      # Space generated by italics/underline
      expected_grid = Scc::Grid.new.insert_text(0, 0, ' ', style.dup)
      style.italics = true
      style.underline = true
      # Space generated by flash
      expected_grid.insert_text(0, 1, ' ', style.dup)
      style.flash = true
      expected_grid.insert_text(0, 2, 'Test', style.dup)
      # Set color via preamble address code to test that too, then set italics/underline via mid-row code, then assign flash via "flash on" miscellaneous control code
      expect(get_captions(caption_at_zero("9420 91c8 912f 94a8 #{test} 942f"))).to eq([Scc::Caption.new(timecode: Timecode.new(6, default_fps), grid: expected_grid)])
    end

    it 'should handle transparent space' do
      # Column 1 should be empty
      expected_grid = Scc::Grid.new.insert_text(0, 0, 'A').insert_text(0, 2, 'A')
      # "A<transparent space>A"
      expect(get_captions(caption_at_zero("9420 91d0 #{a} 91b9 #{a} 942f"))).to eq([Scc::Caption.new(timecode: Timecode.new(5, default_fps), grid: expected_grid)])
    end

    it 'should delete characters behind transparent space' do
      # Column 1 should be empty
      expected_grid = Scc::Grid.new.insert_text(0, 1, 'est')
      # "Test<PAC><transparent space>"
      expect(get_captions(caption_at_zero("9420 91d0 #{test} 91d0 91b9 942f"))).to eq([Scc::Caption.new(timecode: Timecode.new(6, default_fps), grid: expected_grid)])
    end

    it 'should handle standard space' do
      expected_grid = Scc::Grid.new.insert_text(0, 0, 'A A')
      # "A A"
      expect(get_captions(caption_at_zero('9420 91d0 c120 c180 942f'))).to eq([Scc::Caption.new(timecode: Timecode.new(4, default_fps), grid: expected_grid)])
    end

    it 'should handle tab offset' do
      # Space between the As should be empty
      expected_grid = Scc::Grid.new.insert_text(0, 0, 'A').insert_text(0, 2, 'A').insert_text(0, 5, 'A').insert_text(0, 9, 'A')
      # "A<tab offset 1>A<tab offset 2>A<tab offset 3>A"
      expect(get_captions(caption_at_zero("9420 91d0 #{a} 97a1 #{a} 97a2 #{a} 9723 #{a} 942f"))).to eq([Scc::Caption.new(timecode: Timecode.new(9, default_fps), grid: expected_grid)])
    end

    it 'should not delete characters on tab offset' do
      # Space between the As should be empty
      expected_grid = Scc::Grid.new.insert_text(0, 0, 'TAst')
      # "Test<PAC><tab offset 1>A"
      expect(get_captions(caption_at_zero("9420 91d0 #{test} 91d0 97a1 #{a} 942f"))).to eq([Scc::Caption.new(timecode: Timecode.new(7, default_fps), grid: expected_grid)])
    end

    it 'should ignore repeated commands' do
      # There should be only one, not two spaces between the As
      expected_grid = Scc::Grid.new.insert_text(0, 0, 'A').insert_text(0, 2, 'A')
      # "A<transparent space><transparent space>A"
      expect(get_captions(caption_at_zero("9420 91d0 #{a} 91b9 91b9 #{a} 942f"))).to eq([Scc::Caption.new(timecode: Timecode.new(6, default_fps), grid: expected_grid)])
    end

    it 'should not ignore multiply repeated commands' do
      # Now there should be not, not four or one, spaces between the As
      expected_grid = Scc::Grid.new.insert_text(0, 0, 'A').insert_text(0, 3, 'A')
      # "A<transparent space><transparent space<transparent space><transparent space>>A"
      expect(get_captions(caption_at_zero("9420 91d0 #{a} 91b9 91b9 91b9 91b9 #{a} 942f"))).to eq([Scc::Caption.new(timecode: Timecode.new(8, default_fps), grid: expected_grid)])
    end

    it 'should handle delete to end of row' do
      expected_grid = Scc::Grid.new.insert_text(0, 0, 'AAAA')
      # "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA<PAC indent 4><delete to end of row>"
      expect(get_captions(caption_at_zero('9420 91d0 ' + (a + ' ') * 32 + '9152 94a4 942f'))).to eq([Scc::Caption.new(timecode: Timecode.new(36, default_fps), grid: expected_grid)])
    end

    it 'should handle erase displayed memory' do
      expected_grid = Scc::Grid.new.insert_text(0, 0, 'Test')
      # Display "Test", wait 2 frames, erase displayed memory
      # -> should result in an empty caption 3 frames later
      expect(get_captions(caption_at_zero("9420 91d0 #{test} 942f 8080 8080 942c"))).to eq([Scc::Caption.new(timecode: Timecode.new(4, default_fps), grid: expected_grid), Scc::Caption.new(timecode: Timecode.new(7, default_fps))])
    end

    it 'should handle erase non-displayed memory' do
      expected_grid = Scc::Grid.new.insert_text(0, 0, 'A')
      # Insert "Test", delete the non-displayed memory, insert "A" and then flip captions
      expect(get_captions(caption_at_zero("9420 91d0 #{test} 94ae 91d0 #{a} 942f"))).to eq([Scc::Caption.new(timecode: Timecode.new(7, default_fps), grid: expected_grid)])
    end

    it 'should handle special characters' do
      expected_grid = Scc::Grid.new.insert_text(0, 0, '♪')
      expect(get_captions(caption_at_zero('9420 91d0 9137 942f'))).to eq([Scc::Caption.new(timecode: Timecode.new(3, default_fps), grid: expected_grid)])
    end

    it 'should handle multiple timecodes and captions' do
      expected_grid_test = Scc::Grid.new.insert_text(0, 0, 'Test')
      expected_grid_a = Scc::Grid.new.insert_text(0, 0, 'A')
      expected_grid_b = Scc::Grid.new.insert_text(0, 0, 'B')
      caption_text = <<"END"
Scenarist_SCC V1.0

00:00:01:00\t9420 91d0 #{test} 942f 94ae

00:00:02:00\t9420 91d0 #{test} 942f 94ae

00:00:03:00\t942c

00:00:04:00\t9420 91d0 c180 942f

00:00:05:00\t9420 91d0 c280 942f
END
      expect(get_captions(caption_text)).to eq([
        # First caption: Test
        Scc::Caption.new(timecode: Timecode.parse('00:00:01:04', default_fps), grid: expected_grid_test),
        # Caption at 00:00:02:00 should be identical to the first one and thus not get put out
        # At 00:00:03:00: erase displayed caption
        Scc::Caption.new(timecode: Timecode.parse('00:00:03:00', default_fps)),
        # At 00:00:04:00: Display "A"
        Scc::Caption.new(timecode: Timecode.parse('00:00:04:03', default_fps), grid: expected_grid_a),
        # At 00:00:05:00: Display "B" without erasing A beforehand
        Scc::Caption.new(timecode: Timecode.parse('00:00:05:03', default_fps), grid: expected_grid_b)
      ])
    end
  end
end
