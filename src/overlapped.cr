require "bmp"

class WFC::Overlapped
  @depth : UInt32
  @source : BMP
  @patterns : Hash(Array(Bytes), Float64)
  getter patterns
  
  def initialize(@source, @depth, width, height)
    
    raise "Source is too small #{source.width}x#{source.height} for depth #{depth}" if source.width < depth || source.height < depth
    patterns = Hash(Array(Bytes), Int32).new default_value: 0
    0.to @source.height - @depth do |yo|
      0.to @source.width - @depth do |xo|
        pattern = Array(Bytes).new initial_capacity: @depth * @depth 
        0.to @depth - 1 do |yi|
          0.to @depth - 1 do |xi|
            pattern.push @source.data xo + xi, yo + yi
          end
        end
        patterns[pattern] += 1
      end
    end
    total_tiles = (source.height - @depth + 1) * (source.width - @depth + 1)
    @patterns = patterns.transform_values &./ total_tiles
  end

  # 
  def dump_patterns(path)
    i = 0
    @patterns.to_a.each do |pattern, prob|
      dump = BMP.new @depth, @depth, @source.header.bit_per_pixel
      dump.color_table = @source.color_table

      0.to @depth - 1 do |yi|
        0.to @depth - 1 do |xi|
          dump.data xi, yi, pattern[xi + yi * @depth] 
        end
      end

      dump.to_file "#{path}/#{i}_#{prob}.bmp"
      i += 1
    end
  end
end

bmp = BMP.from_file("../Downloads/test.bmp")

bmp.pixel_data = bmp.pixel_data.map do |b|
  b < 100 ? 0u8 : 255u8
end


RED = Bytes [0u8, 0u8, 255u8]
GREEN = Bytes [0u8, 255u8, 0u8]
BLUE = Bytes [255u8, 0u8, 0u8]
BLACK = Bytes [0u8, 0u8, 0u8]

def dump_bmp(bmp)
  puts (String.build do |io|
          pp bmp.pixel_data
   (0...(bmp.height)).each do |y|
     (0...(bmp.width)).each do |x|
       data = bmp.data x, y
      if data == RED
        io << "RED  "
      elsif data == BLACK
        io << "BLACK"
      elsif data == GREEN
        io << "GREEN"
      elsif data == BLUE
        io << "BLUE "
      elsif data == BLACK
        io << "BLACK"
      else
        io << "OTHER"
      end
      io << ", "
    end
    io << '\n'
  end
end)
end

WFC::Overlapped.new(bmp, 3, 0, 0).dump("test")
