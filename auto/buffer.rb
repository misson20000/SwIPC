module SwIPC
  class Buffer
    def initialize(data_type, transfer_type, size, is_array=nil)
      @data_type = data_type
      @transfer_type = transfer_type
      @size = size
      @is_array = is_array
    end

    attr_reader :data_type
    attr_reader :transfer_type
    attr_reader :size
    attr_reader :is_array
    
    def can_merge?(other)
      if @data_type != nil && other.data_type != nil && @data_type != other.data_type then
        return false
      end
      if @transfer_type != other.transfer_type then
        return false
      end
      if @size != nil && other.size != nil && @size != other.size then
        return false
      end
      if @is_array != nil && other.is_array != nil && @is_array != other.is_array then
        return false
      end
      return true
    end

    def merge!(other)
      SwIPC::merge_prop!(self, other, :@data_type)
      SwIPC::merge_prop!(self, other, :@transfer_type)
      SwIPC::merge_prop!(self, other, :@size)
      SwIPC::merge_prop!(self, other, :@is_array)
    end
    
    def to_swipc
      sz_str = "unknown"
      if @size != nil then
        if @size == 0 then
          sz_str = "variable"
        else
          sz_str = "0x" + @size.to_s(16)
        end
      end
      if @is_array then
        if @size != nil && @size != 0 then
          raise "invalid size for array: " + @size.to_s
        end
        return "array<#{@data_type.name || "unknown"}, 0x#{@transfer_type.to_s(16)}>"
      else
        return "buffer<#{@data_type ? @data_type.name : "unknown"}, 0x#{@transfer_type.to_s(16)}, #{sz_str}>"
      end
    end

    def to_s
      to_swipc
    end
  end
end
