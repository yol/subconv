require 'spec_helper'

module Subconv
  describe Scc::Transformer do
    include TestHelpers
    include Subconv

    before(:each) do
      @transformer = Scc::Transformer.new
    end

    it 'should handle empty captions' do
      expect(@transformer.transform([])).to eq([])
    end

    it 'should convert a simple caption' do
      transformed = @transformer.transform(single_scc_caption_with_grid(test_grid))
      expect(transformed).to eq([Caption.new(timespan: t1_2, position: left_top, content: test_content)])
    end

    it 'should auto-close dangling captions' do
      transformed = @transformer.transform([Scc::Caption.new(timecode: t1, grid: test_grid)])
      # Caption should be closed after 5 seconds
      t_end = t1 + Timecode.from_seconds(5.0, default_fps)
      expect(transformed).to eq([Caption.new(timespan: Utility::Timespan.new(t1, t_end), position: left_top, content: test_content)])
    end

    it 'should auto-close a previous caption on caption change' do
      grid = Scc::Grid.new.insert_text(0, 0, 'AAAA')
      transformed = @transformer.transform([Scc::Caption.new(timecode: t1, grid: test_grid), Scc::Caption.new(timecode: t2, grid: grid), Scc::Caption.new(timecode: t3)])
      expect(transformed).to eq([Caption.new(timespan: t1_2, position: left_top, content: test_content), Caption.new(timespan: t2_3, position: left_top, content: root_with_text('AAAA'))])
    end

    it 'should position nodes at the edges at the correct positions' do
      grid = Scc::Grid.new.insert_text(0, 0, 'a').insert_text(0, Scc::GRID_COLUMNS - 1, 'b').insert_text(Scc::GRID_ROWS - 1, 0, 'c').insert_text(Scc::GRID_ROWS - 1, Scc::GRID_COLUMNS - 1, 'd')
      transformed = @transformer.transform(single_scc_caption_with_grid(grid))
      # The exact positions are subject to change when comparison with real SCC data and rendering is done
      expected = [['a', [0.2, 0.1]], ['b', [0.78125, 0.1]], ['c', [0.2, 0.8467]], ['d', [0.78125, 0.8467]]].map { |group|
        Caption.new(timespan: t1_2, position: Position.new(group[1][0], group[1][1]), content: root_with_text(group[0]))
      }
      expect(transformed).to eq(expected)
    end

    def transform_test_style(style)
      @transformer.transform(single_scc_caption_with_grid(Scc::Grid.new.insert_text(0, 0, 'Test', style)))
    end

    it 'should handle italics' do
      style = Scc::CharacterStyle.default
      style.italics = true
      expect(transform_test_style(style)).to eq(single_caption_with_content(ItalicsNode.new([TextNode.new('Test')])))
    end

    it 'should handle underline' do
      style = Scc::CharacterStyle.default
      style.underline = true
      expect(transform_test_style(style)).to eq(single_caption_with_content(UnderlineNode.new([TextNode.new('Test')])))
    end

    it 'should handle flash' do
      style = Scc::CharacterStyle.default
      style.flash = true
      expect(transform_test_style(style)).to eq(single_caption_with_content(FlashNode.new([TextNode.new('Test')])))
    end

    it 'should handle color' do
      style = Scc::CharacterStyle.default
      style.color = Scc::Color::RED
      expect(transform_test_style(style)).to eq(single_caption_with_content(ColorNode.new(:red, [TextNode.new('Test')])))
    end

    it 'should handle all styles combined' do
      style = Scc::CharacterStyle.default
      style.underline = true
      style.italics = true
      style.flash = true
      style.color = Scc::Color::MAGENTA
      # This operates under the assumption that the nodes are sorted with these exact priorities
      # (which may change in the future)
      # Perhaps it would be better to compare independent of the exact order of the nodes
      expect(transform_test_style(style)).to eq(single_caption_with_content(
                                                  ColorNode.new(:magenta, [
                                                    UnderlineNode.new([
                                                      ItalicsNode.new([
                                                        FlashNode.new([
                                                          TextNode.new('Test')
                                                        ])
                                                      ])
                                                    ])
                                                  ])
      ))
    end

    it 'should handle this complicated combination of styles and text' do
      style = Scc::CharacterStyle.default
      grid = Scc::Grid.new
      grid.insert_text(0, 0, 'a')
      style.color = Scc::Color::BLUE
      style.italics = true
      style.flash = true
      grid.insert_text(0, 1, 'b', style.dup)
      style.underline = true
      grid.insert_text(0, 2, 'cde', style.dup)
      style.color = Scc::Color::CYAN
      style.flash = false
      grid.insert_text(0, 5, 'f', style.dup)
      transformed = @transformer.transform(single_scc_caption_with_grid(grid))
      expect(transformed).to eq(single_caption_with_content(
                                  [
                                    TextNode.new('a'),
                                    ItalicsNode.new([
                                      ColorNode.new(:blue, [
                                        FlashNode.new([
                                          TextNode.new('b'),
                                          UnderlineNode.new([
                                            TextNode.new('cde')
                                          ])
                                        ])
                                      ]),
                                      ColorNode.new(:cyan, [
                                        UnderlineNode.new([
                                          TextNode.new('f')
                                        ])
                                      ])
                                    ])
                                  ]
      )
                               )
    end

    it 'should handle this other complicated combination of styles and text' do
      style = Scc::CharacterStyle.default
      grid = Scc::Grid.new
      style.color = Scc::Color::RED
      style.italics = true
      grid.insert_text(0, 0, 'xyz', style.dup)
      style.underline = true
      style.flash = true
      grid.insert_text(0, 3, 'abc', style.dup)
      style.color = Scc::Color::YELLOW
      style.flash = false
      style.italics = false
      grid.insert_text(0, 6, 'jkl', style.dup)
      transformed = @transformer.transform(single_scc_caption_with_grid(grid))
      expect(transformed).to eq(single_caption_with_content(
                                  [
                                    ColorNode.new(:red, [
                                      ItalicsNode.new([
                                        TextNode.new('xyz'),
                                        UnderlineNode.new([
                                          FlashNode.new([
                                            TextNode.new('abc')
                                          ])
                                        ])
                                      ])
                                    ]),
                                    ColorNode.new(:yellow, [
                                      UnderlineNode.new([
                                        TextNode.new('jkl')
                                      ])
                                    ])
                                  ]
      )
                               )
    end
  end
end
