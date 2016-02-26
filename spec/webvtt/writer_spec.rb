require 'spec_helper'

module Subconv
  describe WebVtt::Writer do
    include TestHelpers
    include Subconv

    let(:header) { "WEBVTT\n\n" }
    # Header including one cue from t1 to t2 at top left
    let(:cue_header) { header + "00:00:00.400 --> 00:00:00.800 align:start line:10.000% position:20.000%\n" }

    before(:each) do
      @writer = WebVtt::Writer.new
    end

    def write(captions)
      stringio = StringIO.new
      @writer.write(stringio, captions)
      # Strip whitespace from the end of the string since it doesn't particularly matter
      stringio.string.rstrip
    end

    it 'should write out a single caption' do
      expect(write(single_caption_with_content('Test'))).to eq(cue_header + 'Test')
    end

    it 'should write out multiple captions' do
      captions = [
        Caption.new(timespan: t1_2, position: left_top, content: root_with_text('Test 1'), align: :start),
        Caption.new(timespan: t1_2, position: Position.new(0.2, 0.3), content: root_with_text('Test 2'), align: :start),
        Caption.new(timespan: Utility::Timespan.new(Timecode.new(25, default_fps), Timecode.new(35, default_fps)), position: left_top, content: root_with_text('Test 3'), align: :start)
      ]

      expected = header + <<"END".rstrip
00:00:00.400 --> 00:00:00.800 align:start line:10.000% position:20.000%
Test 1

00:00:00.400 --> 00:00:00.800 align:start line:30.000% position:20.000%
Test 2

00:00:01.000 --> 00:00:01.400 align:start line:10.000% position:20.000%
Test 3
END
      expect(write(captions)).to eq(expected)
    end

    it 'support simple positioning and alignment' do
      captions = [
        Caption.new(timespan: t1_2, position: :top, content: root_with_text('Test 1'), align: :start),
        # align:middle should not be output as it is the default
        Caption.new(timespan: t2_3, position: :bottom, content: root_with_text('Test 2'), align: :middle)
      ]

      expected = header + <<"END".rstrip
00:00:00.400 --> 00:00:00.800 align:start line:5%
Test 1

00:00:00.800 --> 00:00:01.200 line:-1,end
Test 2
END
      expect(write(captions)).to eq(expected)
    end

    it 'should support italics' do
      expect(write(single_caption_with_content(ItalicsNode.new([TextNode.new('Test')])))).to eq(cue_header + '<i>Test</i>')
    end

    it 'should support underline' do
      expect(write(single_caption_with_content(UnderlineNode.new([TextNode.new('Test')])))).to eq(cue_header + '<u>Test</u>')
    end

    it 'should support flash' do
      expect(write(single_caption_with_content(FlashNode.new([TextNode.new('Test')])))).to eq(cue_header + '<c.blink>Test</c>')
    end

    it 'should support colors' do
      expect(write(single_caption_with_content(ColorNode.new(:magenta, [TextNode.new('Test')])))).to eq(cue_header + '<c.magenta>Test</c>')
    end

    it 'should escape special characters' do
      expect(write(single_caption_with_content('<i>&Test</i>'))).to eq(cue_header + '&lt;i&rt;&amp;Test&lt;/i&rt;')
    end

    it 'should support complicated combinations of styles' do
      nodes = [
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
      expect(write(single_caption_with_content(nodes))).to eq(cue_header + 'a<i><c.blue><c.blink>b<u>cde</u></c></c><c.cyan><u>f</u></c></i>')
    end
  end
end
