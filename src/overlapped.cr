require "bmp"
require "./superimposed"

# Two dimmensional wave function collapse.
# TODO: make it input source agnostic and provides helper function to build the patterns and output.
# TODO: move the pattern derivations somewhere else
# TODO: not overlapped, rename.
# TODO: bisected backups, rollback
class WFC::Overlapped
  alias Pattern = Array(Bytes)

  class Metadata

    @[Flags]
    enum Borders : UInt8
      TopNo
      TopYes
      BottomNo
      BottomYes
      LeftNo
      LeftYes
      RightNo
      RightYes
    end

    @[Flags]
    enum Directions : UInt8
      Top
      Bottom
      Left
      Right
    end

    property pattern : Pattern
    property frequency = 0u64
    property borders = Borders::None
    property top = {} of Metadata => Float64
    property bottom = {} of Metadata => Float64
    property left = {} of Metadata => Float64
    property right = {} of Metadata => Float64

    def initialize(@pattern, @borders) end
  end
  
  @depth : UInt32
  @source : BMP
  @patterns = {} of Pattern => Metadata
  @target : Superimposed(Metadata)
  @width : Int32
  @height : Int32
  @propagations : Array(Directions)
  getter patterns
  @lowest_entropy = 0
  @lowest_entropy_index = {0, 0}
  @random = Random.new
  def initialize(@source, @depth, @width, @height, seed = nil, border = true)
    raise "Target size is too low" if @width < 1 || @height < 1
    raise "Source is too small #{source.width}x#{source.height} for depth #{depth}" if source.width < depth || source.height < depth
    @random = Random.new seed, 0u64 if seed
    default_border = border ? Borders::None : Borders::All
    adjacencies = Array(Metadata?).new size: (@source.height - @depth + 1) * (@source.width - @depth + 1), value: nil
    @propagations = Array(Directions).new size: @height * @width, value: Directions::None
    0.to @source.height - @depth do |yo|
      0.to @source.width - @depth do |xo|
        pattern = Pattern.new initial_capacity: @depth * @depth 
        0.to @depth - 1 do |yi|
          0.to @depth - 1 do |xi|
            pattern.push @source.data xo + xi, yo + yi
          end
        end
        meta = @patterns[pattern]? || (@patterns[pattern] = Metadata.new pattern, border)
        pattern = meta.pattern
        adjacencies[xo + yo * (@source.width - @depth + 1)] = meta
        meta.frequency += 1
      end
    end

    0.to @source.height - @depth do |yo|
      0.to @source.width - @depth do |xo|
        meta = adjacencies[xo + yo * (@source.width - @depth + 1)].not_nil!
        if yo == 0
          meta.borders |= :top_yes
        else
          meta.borders |= :top_no
          top = adjacencies[xo + (yo - 1) * (@source.width - @depth + 1)].not_nil!
          meta.top[top] = (meta.top[top]? || 0f64) + 1u64
        end

        if yo == @source.height - @depth
          meta.borders |= :bottom_yes
        else
          meta.borders |= :bottom_no
          bottom = adjacencies[xo + (yo + 1) * (@source.width - @depth + 1)].not_nil!
          meta.bottom[bottom] = (meta.bottom[bottom]? || 0f64) + 1u64
        end

        if xo == 0
          meta.borders |= :left_yes
        else
          meta.borders |= :left_no
          left = adjacencies[(xo - 1) + yo * (@source.width - @depth + 1)].not_nil!
          meta.left[left] = (meta.left[left]? || 0f64) + 1u64
        end

        if xo == @source.width - @depth
          meta.borders |= :right_yes
        else
          meta.borders |= :right_yes
          right = adjacencies[(xo + 1) + yo * (@source.width - @depth + 1)].not_nil!
          meta.right[right] = (meta.right[right]? || 0f64) + 1u64
        end
      end
    end

    @patterns.values.each do |meta|
      meta.top.transform_values { |value| value / meta.top.size }
      meta.bottom.transform_values { |value| value / meta.bottom.size }
      meta.left.transform_values { |value| value / meta.left.size }
      meta.right.transform_values { |value| value / meta.right.size }
    end
    @target = Superimposed(Metadata).new({@width, @height}, @patterns.values) 
    constrain_borders
  end

  # Fully collapse the target
  def fully_collapse
    fully_collpased = false
    while !fully_collpased
      fully_collapsed = collapse
    end
  end

  # Apply the order constraint to the whole target
  def constrain_borders
    (0...@height).each do |y|
      (0...@width).each do |x|
        if y == 0
          state[{x, y}] = state[{x, y}].select &.borders.top_yes?
        else
          state[{x, y}] = state[{x, y}].select &.borders.top_no?
        end
        if y == @height - 1
          state[{x, y}] = state[{x, y}].select &.borders.bottom_yes?
        else
          state[{x, y}] = state[{x, y}].select &.borders.bottom_no?
        end
        if x == 0
          state[{x, y}] = state[{x, y}].select &.borders.left_yes?
        else
          state[{x, y}] = state[{x, y}].select &.borders.left_no?
        end
        if x == @width - 1
          state[{x, y}] = state[{x, y}].select &.borders.right_yes?
        else
          state[{x, y}] = state[{x, y}].select &.borders.right_no?
        end
      end
    end
  end

  # Update the superimposed state of the given cell according to given directions.
  # Return true if the state changed, false otherwise.
  def constrain(x, y, mutated_neighboor : Directions)
    current = @target[{x, y}]
    new = current.select do |state|
      ((!mutated_neighboor.top?) ||
      (@target[{x, y - 1}].any? &.bottom.includes? state)) &&
      ((!mutated_neighboor.bottom?) ||
      (@target[{x, y + 1}].any? &.top.includes? state)) &&
      ((!mutated_neighboor.left?) ||
      (@target[{x - 1, y}].any? &.right.includes? state)) &&
      ((!mutated_neighboor.right?) ||
      (@target[{x + 1, y}].any? &.left.includes? state))
    end

    raise "Contradiction reached" if current.size == 0
    if current.size != new.size
      @target[{x, y}] = new
      return true
    else
      return false
    end
  end

  # Propagate the whole target assuming the given location has muted.
  # If *recursive* is false, schedule for propagation only.
  # Return true if the target is fully collapsed.
  def propagate(x ,y, recurisve = true)
    @propagations[y * @width + x + 1] |= Directions::Left if x + 1 < @width
    @propagations[y * @width + x - 1] |= Directions::Right if x > 0
    @propagations[(y + 1) * @width + x] |= Directions::Top if y + 1 < @height
    @propagations[(y - 1) * @width + x] |= Directions::Bottom if y > 0
    if recurisve
      propagate
    else
      false
    end
  end

  # Propagate any pending modifications to the whole target.
  # Return true if the target is fully collapsed.
  def propagate
    any_constrained = true
    fully_collapsed = true
    while any_constrained do
      any_constrained = false
      fully_collapsed = true
      (0...@height).each do |y|
        (0...@width).each do |x|
          d = @propagations[x + y * @width]
          unless d.none?
            constrained = constrain x, y, d 
            @propagations[x + y * @width] = Directions::None  
            propagate x, y, recursive: false if constrained
            any_constrained |= constrained
          end
          fully_collapsed &= @target[{x, y}].size == 1
        end
      end
    end
    fully_collapsed
  end

  # Collapse the given location to the given state.
  # Return true if the target is fully collapsed.
  def collapse(x, y, state)
    @target[{x, y}] = {state}
    propagate x, y
  end

  # Collapse the given location to a possible state.
  # Return true if the target is fully collapsed.
  def collapse(x, y)
    states = @target[{x, y}]
    r = @random.rand states.sum &.frequency
    s = 0
    states.each do |state|
      s += state.frequency
      return collapse(x, y, state) if r < s
    end
    raise "Couldn't find a state to collpase to"
  end

  # pick a location and collapse it.
  # Return true if the target is fully collapsed.  
  def collapse
    collapse *@lowest_entropy_index
  end

  # Assume fully collapsed
  def dump_target(path)
    dump = BMP.new @width * @depth, @height * @depth, @source.header.bit_per_pixel
    r = g = b = 0u64
    dump.color_table = @source.color_table
    (0...@height).each do |yo|
      (0...@width).each do |xo|
        pattern = @target[{xo, yo}].pattern
        (0...@depth).each do |yi|
          (0...@depth).each do |xi|
            dump.data xo * @depth + xi, yo * @depth + xo, pattern[xi + yi * @depth]
          end
        end
      end
    end
    dump.to_file path
  end
end

bmp = BMP.from_file("../Downloads/test.bmp")

bmp.pixel_data = bmp.pixel_data.map do |b|
  b < 100 ? 0u8 : 255u8
end

pp WFC::Overlapped.new(bmp, 3, 7, 7).tap(&.fully_collapse).dump_target "/tmp/target.bmp"
`feh --force-aliasing /tmp/target.bmp`
