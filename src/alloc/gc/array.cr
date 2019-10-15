GC_ARRAY_HEADER_TYPE = 0xFFFF_FFFF.to_usize
GC_ARRAY_HEADER_SIZE = sizeof(USize) * 2

class GcArray(T)
  @capacity : Int32
  getter capacity

  def size
    return 0 if @capacity == 0
    @buffer[1].to_i32
  end

  protected def size=(new_size)
    return if @capacity == 0
    @buffer[1] = new_size.to_usize
  end

  private def malloc_bytes(nelem)
    nelem.to_usize * sizeof(Void*) + GC_ARRAY_HEADER_SIZE
  end

  private def capacity_for_ptr(ptr)
     ((KernelArena.block_size_for_ptr(ptr) -
      (GC_ARRAY_HEADER_SIZE + sizeof(LibCrystal::GcNode))) // sizeof(T)).to_i32
  end

  private def new_buffer(new_capacity)
    if size > new_capacity
      panic "size must be smaller than capacity"
    elsif !@buffer.nil? && capacity_for_ptr(@buffer) >= new_capacity
      return
    end
    old_size = size
    old_buffer = @buffer
    @buffer = Pointer(UInt8).malloc(malloc_bytes(new_capacity)).as(USize*)
    memcpy(@buffer.as(UInt8*), old_buffer.as(UInt8*), malloc_bytes(old_size))
  end

  def initialize
    @capacity = 0
    @buffer = Pointer(USize).null
  end

  def initialize(initial_capacity : Int32)
    @capacity = initial_capacity
    if initial_capacity > 0
      @buffer = Pointer(UInt8).malloc(malloc_bytes(initial_capacity)).as(USize*)
      @buffer[0] = GC_ARRAY_HEADER_TYPE
      @buffer[1] = 0u32
    else
      @buffer = Pointer(USize).null
    end
  end

  def clone
    GcArray(T).build(size) do |buffer|
      size.times do |i|
        buffer[i] = to_unsafe[i]
      end
      size
    end
  end

  def self.build(capacity : Int) : self
    ary = GcArray(T).new(capacity)
    ary.size = (yield ary.to_unsafe).to_i
    ary
  end

  def self.new(size : Int, &block : Int32 -> T)
    GcArray(T).build(size) do |buffer|
      size.to_i.times do |i|
        buffer[i] = yield i
      end
      size
    end
  end

  def to_unsafe
    (@buffer + 2).as(T*)
  end

  def [](idx : Int)
    panic "accessing out of bounds!" unless 0 <= idx && idx < size
    to_unsafe[idx]
  end

  def []?(idx : Int) : T?
    return nil unless 0 <= idx && idx <= size
    to_unsafe[idx]
  end

  def []=(idx : Int, value : T)
    panic "setting out of bounds!" unless 0 <= idx && idx < size
    to_unsafe[idx] = value
  end

  def push(value : T)
    if size < capacity
      to_unsafe[size] = value
      self.size = size + 1
    else
      new_buffer(size + 1)
      to_unsafe[size] = value
      self.size = size + 1
    end
  end

  def each
    i = 0
    while i < size
      yield to_unsafe[i]
      i += 1
    end
  end
end
