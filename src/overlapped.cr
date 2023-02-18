require "bmp"
require "./superimposed"

# Two dimmensional overlapped wave function collapse.
# TODO: make it input source agnostic and provides helper function to build the patterns and output.
# TODO: move the pattern derivations somewhere else
# TODO: not overlapped, rename.
class WFC::Overlapped
  alias Pattern = Array(Bytes)

  # TODO: adjacencies frequencies ?
  # NOTE: Border can be: false: can be at border, true: can be ?
  # TODO: it should be a (cannot, can, should) instead.
  class Metadata
    property pattern : Pattern
    property frequency : Float64 = 0u64
    property border_top : Bool
    property border_bottom : Bool
    property border_left : Bool
    property border_right : Bool
    property top :  Set(Metadata)
    property bottom : Set(Metadata)
    property left : Set(Metadata)
    property right : Set(Metadata)
    def initialize(@pattern, border = false)
      @border_top = border
      @border_bottom = border
      @border_left = border
      @border_right = border
      @top = Set(Metadata).new
      @bottom = Set(Metadata).new
      @left = Set(Metadata).new
      @right = Set(Metadata).new
    end
  end
  
  @depth : UInt32
  @source : BMP
  @patterns = {} of Pattern => Metadata
  @target : Superimposed(Metadata)
  getter patterns
  
  def initialize(@source, @depth, width, height, border = true)
    raise "Source is too small #{source.width}x#{source.height} for depth #{depth}" if source.width < depth || source.height < depth
    adjacencies = Array(Metadata?).new size: (@source.height - @depth + 1) * (@source.width - @depth + 1), value: nil
    0.to @source.height - @depth do |yo|
      0.to @source.width - @depth do |xo|
        pattern = Pattern.new initial_capacity: @depth * @depth 
        0.to @depth - 1 do |yi|
          0.to @depth - 1 do |xi|
            pattern.push @source.data xo + xi, yo + yi
          end
        end
        meta = @patterns[pattern]? || (@patterns[pattern] = Metadata.new pattern)
        pattern = meta.pattern
        adjacencies[xo + yo * (@source.width - @depth + 1)] = meta
        meta.frequency += 1       
      end
    end

    0.to @source.height - @depth do |yo|
      0.to @source.width - @depth do |xo|
        meta = adjacencies[xo + yo * (@source.width - @depth + 1)].not_nil!
        if yo == 0
          meta.border_top = true
        else
          meta.top.add adjacencies[xo + (yo - 1) * (@source.width - @depth + 1)].not_nil!
        end

        if yo == @source.height - @depth
          meta.border_bottom = true
        else
          meta.bottom.add adjacencies[xo + (yo + 1) * (@source.width - @depth + 1)].not_nil!
        end

        if xo == 0
          meta.border_left = true
        else
          meta.left.add adjacencies[(xo - 1) + yo * (@source.width - @depth + 1)].not_nil!
        end

        if xo == @source.width - @depth
          meta.border_right = true
        else
          meta.right.add adjacencies[(xo + 1) + yo * (@source.width - @depth + 1)].not_nil!
        end
      end
    end

    total_tiles = (source.height - @depth + 1) * (source.width - @depth + 1)
    @patterns.transform_values { |meta| meta.frequency /= total_tiles }
    @target = Superimposed(Metadata).new({width, height}, @patterns.values) # this is where we decide if overlapping or not. Lets try not overlapping ok ?
  end

  # More complex pattern generation:
  # includes adjacency rules: each pattern can be top/bottom/right/left adjacent to [these patterns], and optionnaly to border (default to all ok with all border).
  # TBH this is not overlapped anymore;

  # MAYBE: overlapped, each pixel has a superimposed state of patterns starting there, but pattern probablities are kept boolean ?
  # It allows propagation stabilization (state do not change = do not propagte, change => propagate but entropy is reduced permantently. Real does not allows stabilization in all case, and not propagating if unstabilized yield issues, their state is not up to date and later collapsing will propagate errors.
  # Maybe two layered: pattern level and pixel level (used for manual constraining and visualisation ?)
  # Callback at various steps for viz ?
  # Optional n bisected backups for rollback in case of conflict ?
  # Seed ?
  

  def loop
    # pick a pixel with low entropy (few possibilities left). How the fuck we store this ? Naive way is to superimpse color existing color values.
     # memory optimization would be to have all fully unobserved pixel reference the same superimposed states
    # collapse it to one of the possible states
    # propagate: each nxb region containing this pixel, each pattern   
  end

  def constrain(x, y)
    # for each direction
    # remove possible pattern if:
    # - location is a border and tile does not allows border (idk to rework)
    # - not in the adjacencies of any of the possible patterns of the neighboor
    # IF the state changed return true, else false (so caller know it must propagate or not)
  end

  def propagate()
    # apply constraint, if state changed propagate around.
    # How to avoid recursivity ?
    # maybe have for each pattern location marked for propagation.
    # When we treat a location, we mark it for no propagation. if it change: we mark neighboor for propagation.
    # We keep handling marked location until there is more.
    # Try to select next location by searching near previous one for optimization and visual satisfaction.
  end

  def collapse()
    # pick a location, compute probability according to state, frequencies of state
    # TODO: account for neighboor adjacency frequencies instead ? SHould resolve to the same overall local freq.
    # then propagate from it.
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

pp WFC::Overlapped.new(bmp, 3, 7, 7)
#.dump("test")
