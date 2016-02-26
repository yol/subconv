require 'spec_helper'

module Subconv
  describe CaptionFilter do
    include TestHelpers

    it 'should not do anything by default' do
      expected, captions = caption_filter_process({}) { caption_all_node_types }
      expect(captions).to eq(expected)
    end

    it 'should remove color nodes' do
      expected, captions = caption_filter_process(remove_color: true) { caption_all_node_types }
      expected[0].content.children[0] = TextNode.new('1')
      expect(captions).to eq(expected)
    end

    it 'should remove flash nodes' do
      expected, captions = caption_filter_process(remove_flash: true) { caption_all_node_types }
      expected[0].content.children[1] = TextNode.new('2')
      expect(captions).to eq(expected)
    end

    it 'should remove color and flash nodes' do
      expected, captions = caption_filter_process(remove_color: true, remove_flash: true) { caption_all_node_types }
      expected[0].content.children[0] = TextNode.new('12')
      expected[0].content.children.delete_at 1
      expect(captions).to eq(expected)
    end

    it 'should remove nodes recursively' do
      captions = single_caption_with_content([
        TextNode.new('a'),
        ItalicsNode.new([
          ColorNode.new(:blue, [
            TextNode.new('b'),
            FlashNode.new([
              TextNode.new('c'),
              UnderlineNode.new([
                TextNode.new('de')
              ])
            ])
          ]),
          ColorNode.new(:cyan, [
            UnderlineNode.new([
              TextNode.new('f')
            ])
          ])
        ])
      ])
      CaptionFilter.new(remove_color: true, remove_flash: true).process!(captions)
      expected = single_caption_with_content([
        TextNode.new('a'),
        ItalicsNode.new([
          TextNode.new('bc'),
          UnderlineNode.new([
            TextNode.new('de')
          ]),
          UnderlineNode.new([
            TextNode.new('f')
          ])
        ])
      ])
      expect(captions).to eq(expected)
    end

    context 'when converting XY positions to simple top/bottom centered positions' do
      it 'should remove the X position' do
        expected, captions = caption_filter_process(xy_position_to_top_or_bottom: true) {
          [
            Caption.new(timespan: t1_2, position: Position.new(0.1, 0.1), content: root_with_text('Test 1'), align: :start),
            Caption.new(timespan: t2_3, position: Position.new(0.1, 0.7), content: root_with_text('Test 2'), align: :start)
          ]
        }
        expected[0].position = :top
        expected[1].position = :bottom
        expected[0].align = :middle
        expected[1].align = :middle
        expect(captions).to eq(expected)
      end

      it 'should support simultaneous top and bottom captions' do
        expected, captions = caption_filter_process(xy_position_to_top_or_bottom: true) {
          [
            Caption.new(timespan: t1_2, position: Position.new(0.1, 0.1), content: root_with_text('Test 1'), align: :start),
            Caption.new(timespan: t1_2, position: Position.new(0.1, 0.7), content: root_with_text('Test 2'), align: :start)
          ]
        }
        expected[0].position = :top
        expected[1].position = :bottom
        expected[0].align = :middle
        expected[1].align = :middle
        expect(captions).to eq(expected)
      end

      it 'should not split continuous on-screen lines starting in the top region to top and bottom' do
        expected, captions = caption_filter_process(xy_position_to_top_or_bottom: true) {
          [
            Caption.new(timespan: t1_2, position: Position.new(0.1, 0.49), content: root_with_text('Test 1'), align: :start),
            Caption.new(timespan: t1_2, position: Position.new(0.1, 0.51), content: root_with_text('Test 2'), align: :start),
            Caption.new(timespan: t2_3, position: Position.new(0.1, 0.52), content: root_with_text('Test 2'), align: :start)
          ]
        }
        expected[0].position = :top
        expected[1].position = :top
        expected[2].position = :bottom
        expected[0].align = :middle
        expected[1].align = :middle
        expected[2].align = :middle
        expect(captions).to eq(expected)
      end

      it 'should merge captions in the same region when requested' do
        expected, captions = caption_filter_process(xy_position_to_top_or_bottom: true, merge_by_position: true) {
          [
            Caption.new(timespan: t1_2, position: Position.new(0.1, 0.1), content: root_with_text('Test 1'), align: :start),
            Caption.new(timespan: t1_2, position: Position.new(0.1, 0.2), content: root_with_text('Test 2'), align: :start),
            Caption.new(timespan: t1_2, position: Position.new(0.1, 0.7), content: root_with_text('Test 3'), align: :start),
            Caption.new(timespan: t1_2, position: Position.new(0.1, 0.8), content: root_with_text('Test 4'), align: :start)
          ]
        }
        expected.delete_at 1
        expected.delete_at 2
        expected[0].position = :top
        expected[1].position = :bottom
        expected[0].content.children[0].text = "Test 1\nTest 2"
        expected[1].content.children[0].text = "Test 3\nTest 4"
        expected[0].align = :middle
        expected[1].align = :middle
        expect(captions).to eq(expected)
      end

      it 'should not merge captions with different timecodes' do
        expected, captions = caption_filter_process(xy_position_to_top_or_bottom: true, merge_by_position: true) {
          [
            Caption.new(timespan: t1_2, position: Position.new(0.1, 0.1), content: root_with_text('Test 1'), align: :start),
            Caption.new(timespan: t1_2, position: Position.new(0.1, 0.6), content: root_with_text('Test 2'), align: :start),
            Caption.new(timespan: t2_3, position: Position.new(0.1, 0.7), content: root_with_text('Test 3'), align: :start),
            Caption.new(timespan: t2_3, position: Position.new(0.1, 0.8), content: root_with_text('Test 4'), align: :start)
          ]
        }
        expected.delete_at 3
        expected[0].position = :top
        expected[1].position = :bottom
        expected[2].position = :bottom
        expected[2].content.children[0].text = "Test 3\nTest 4"
        expected[0].align = :middle
        expected[1].align = :middle
        expected[1].align = :middle
        expect(captions).to eq(expected)
      end
    end
  end
end
