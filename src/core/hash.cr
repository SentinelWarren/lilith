class Hash(K, V) < Markable

  struct Entry(K, V)
    getter hash, key, value
    def initialize(@hash : UInt64, @key : K, @value : V)
    end

    def self.empty
      key = uninitialized K
      value = uninitialized V
      new 0u64, key, value
    end

    def empty?
      @hash == 0u64
    end
  end

  INITIAL_CAPACITY = 2

  @entries = Pointer(Entry(K, V)).null
  @size = 0
  @occupied = 0
  getter size, occupied

  private def recalculate_size
    @size = (Allocator.block_size_for_ptr(@entries) // sizeof(Entry(K, V))).lowest_power_of_2
  end

  def initialize(initial_capacity : Int = 0)
    write_barrier do
      if initial_capacity > 0
        @entries = Pointer(Entry(K, V)).malloc_atomic(initial_capacity)
        initial_capacity.times do |i|
          @entries[i] = Entry(K, V).empty
        end
        recalculate_size
      end
    end
  end

  def get_key_with_hasher(key, hasher)
    return if @size == 0
    idx = key.hash(hasher).result & (@size - 1)
    # Serial.print idx, ' ', @entries.as(Void*), '\n'
    while idx < @size
      entry = @entries[idx]
      unless entry.empty?
        return entry.value if entry.key == key
      end
      idx += 1
    end
  end

  def []?(key)
    get_key_with_hasher(key, Hasher.new)
  end

  def [](key)
    self[key]? || abort "key not found"
  end

  private def find_slot(key, idx)
    while idx < @size
      if @entries[idx].empty?
        @occupied += 1
        return idx
      elsif @entries[idx].key == key
        return idx 
      end
      idx += 1
    end
  end

  def []=(key : K, value : V, hasher = Hasher.new)
    write_barrier
    hash = key.hash(hasher).result
    # create entry list if empty
    if @entries.null?
      # resize
      @entries = Pointer(Entry(K, V)).malloc_atomic(INITIAL_CAPACITY)
      INITIAL_CAPACITY.times do |i|
        @entries[i] = Entry(K, V).empty
      end
      recalculate_size
      # insert
      idx = hash & (@size - 1)
      @entries[idx] = Entry.new(hash, key, value)
      @occupied = 1
      write_barrier_end
      return value
    end
    # expand if we reached load factor
    # occupied / size >= 1/2 => 2*occupied >= size
    rehash(barrier: false) if @occupied * 2 >= @size
    # search a slot and set it
    while true
      idx = hash & (@size - 1)
      if slot = find_slot(key, idx)
        @entries[slot] = Entry.new(hash, key, value)
        write_barrier_end
        return value
      end
      rehash(barrier: false)
    end
  end

  def rehash(size_mul = 2, barrier = true)
    write_barrier if barrier
    old_entries = @entries
    old_size = @size

    @size *= size_mul
    @entries = Pointer(Entry(K, V)).malloc_atomic(@size)
    recalculate_size
    @size.times do |i|
      @entries[i] = Entry(K, V).empty
    end

    old_size.times do |i|
      old_entry = old_entries[i]
      unless old_entry.empty?
        new_idx = old_entry.hash & (@size - 1)
        if @entries[new_idx].empty?
          # this bucket is empty so we can just insert it
          #Serial.print "idx: ", new_idx, ' ', old_entry.key, '\n'
          @entries[new_idx] = old_entry
        else
          # search for next available bucket
          while new_idx < @size
            break if @entries[new_idx].empty?
            new_idx += 1
          end
          if new_idx == @size
            # nope, we can't find one!
            @entries = old_entries
            @size = old_size
            #Serial.print @size, ' ', size_mul, '\n'
            return rehash(size_mul * 2, barrier)
          end
          # insert it
          #Serial.print "idx: ", new_idx, ' ', old_entry.key, '\n'
          @entries[new_idx] = old_entry
        end
      end
    end
    write_barrier_end if barrier
  end
  
  @[NoInline]
  def mark(&block : Void* ->)
    yield @entries.as(Void*)
    @size.times do |i|
      entry = @entries[i]
      unless entry.empty?
        {% unless K < Int || K < Struct %}
          yield entry.key.as(Void*)
        {% end %}
        {% unless K < Int || K < Struct %}
          yield entry.value.as(Void*)
        {% end %}
      end
    end
  end

end
