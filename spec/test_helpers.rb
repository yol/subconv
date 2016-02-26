module Subconv
  module TestHelpers
    def default_fps
      25
    end

    def t1
      Timecode.new(10, default_fps)
    end

    def t2
      Timecode.new(20, default_fps)
    end

    def t3
      Timecode.new(30, default_fps)
    end

    def t1_2
      Utility::Timespan.new(t1, t2)
    end

    def t2_3
      Utility::Timespan.new(t2, t3)
    end

    def test_grid
      Scc::Grid.new.insert_text(0, 0, 'Test')
    end

    def test_content
      RootNode.new([TextNode.new('Test')])
    end

    def left_top
      Position.new(0.2, 0.1)
    end

    def single_scc_caption_with_grid(grid)
      [Scc::Caption.new(timecode: t1, grid: grid), Scc::Caption.new(timecode: t2)]
    end

    def single_caption_with_content(content)
      # Auto-promote the content to a TextNode if necessary
      content = TextNode.new(content) if content.instance_of?(String)
      # Auto-promote the content to an array if necessary
      content = [content] unless content.instance_of?(Array)
      [Caption.new(timespan: t1_2, position: left_top, content: RootNode.new(content), align: :start)]
    end

    def root_with_text(text)
      RootNode.new([TextNode.new(text)])
    end

    def caption_all_node_types
      single_caption_with_content(
        [
          ColorNode.new(:blue, [TextNode.new('1')]),
          FlashNode.new([TextNode.new('2')]),
          ItalicsNode.new([TextNode.new('3')]),
          UnderlineNode.new([TextNode.new('4')])
        ]
      )
    end

    def caption_filter_process(options)
      original = yield
      processed = yield
      CaptionFilter.new(options).process!(processed)
      [original, processed]
    end
  end
end
