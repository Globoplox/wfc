require "bit_array"

class Constraint(T)
  
  property dimensions : Indexable(Int32)
  property state : BitArray
  property components : Indexable(T)

  @coordinate_multiplicator : Indexable(Int32)
  def initialize(@dimensions, @components)
    raise "There is no point in constraining with less than 2 possibilities" if @components.size < 1
    size = @dimensions.reduce? { |a,b| a * b } || 0u32
    raise "Constraint dimensions can be 0" if size == 0
    @state = BitArray.new size * @components.size, true
    @coordinate_multiplicator = (0...(@dimensions.size)).map { |i|
      v = 1
      (i + 1).upto @dimensions.size - 1 do |i|
        v *= @dimensions[i]
      end
      v
    }
  end
  
  def []=(coordinates : Indexable(Int32), values : Indexable(T))
    raise "Coordinates depth must be #{@dimensions.size}" if @dimensions.size != coordinates.size
    offset = coordinates.zip(@coordinate_multiplicator).map { |a, b| a * b }.sum* @components.size
    0.upto @components.size - 1 do |i|
      @state[offset + i] = @components[i].in? values
    end
    @dirty = true
  end

  def [](coordinates : Indexable(Int32)) : Indexable(T)
    raise "Coordinates depth must be #{@dimensions.size}" if @dimensions.size != coordinates.size
    offset = coordinates.zip(@coordinate_multiplicator).map { |a, b| a * b }.sum * @components.size
    values = [] of T
    0.upto @components.size - 1 do |i|
      values << @components[i] if @state[offset + i]
    end
    values
  end

  def apply_constraint
  end

  def apply_constraint_until_clean
    loop do
      @dirty = false
      apply_constraint
      break unless @dirty
    end
  end

  def entropy
    
  end

end
