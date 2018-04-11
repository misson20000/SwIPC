require_relative "util.rb"

module SwIPC
  class Command
    def initialize(context, id, source)
      @context = context
      @id = id
      @sources = [source]
      @name = nil
      @buffers = nil
      @pid = nil
      @inbytes = nil
      @outbytes = nil
      @ininterfaces = nil
      @outinterfaces = nil
      @inhandles = nil
      @outhandles = nil
      @args_raw = []
    end

    def inspect
      "##{id}: #{name}, buffers: [#{buffers ? buffers.join(", ") : "unknown"}], pid: #{pid}, inbytes: #{inbytes}, outbytes: #{outbytes}, ininterfaces: #{ininterfaces}, outinterfaces: #{outinterfaces}, inhandles: #{inhandles}, outhandles: #{outhandles}"
    end
    
    attr_reader :id
    attr_reader :name
    attr_reader :buffers
    attr_reader :pid
    attr_reader :inbytes
    attr_reader :outbytes
    attr_reader :ininterfaces
    attr_reader :outinterfaces
    attr_reader :inhandles
    attr_reader :outhandles
    attr_reader :inargs
    attr_reader :outargs
    attr_reader :args_raw
    
    attr_reader :sources

    attr_accessor :decorators
    
    def add_data(key, value)
      case key
      when "inbytes"
        @inbytes = value
      when "outbytes"
        @outbytes = value
      when "buffers"
        @buffers = value.map do |b| Buffer.new(nil, b, nil) end
      when "pid"
        @pid = value
      when "ininterfaces"
        @ininterfaces = value
      when "outinterfaces"
        @outinterfaces = value
      when "inhandles"
        @inhandles = value
      when "outhandles"
        @outhandles = value
      when "name"
        @name = value
      else
        raise "unknown data key: " + key
      end
    end

    def add_args(data, has_args, has_info, version)
      if has_info then
        @buffers||= []
        @pid||= false
        @ininterfaces||= []
        @outinterfaces||= []
        @inhandles||= []
        @outhandles||= []
        @inargs||= []
        @outargs||= []
      end
      data.each do |arg|
        type = arg[0]
        info = arg[1]
        if info then
          case info.before
          when "Buffer"
            index = SwIPC::parse_int(info.inside[0])
            tx_type = SwIPC::parse_int(info.inside[1])
            size = SwIPC::parse_int(info.inside[2])
            data_type = nil
            is_array = false
            
            if type then
              case type.before
              when "Out"
                data_type = type.inside[0].to_s
              when "InArray"
                data_type = type.inside[0].to_s
                is_array = true
              when "OutArray"
                data_type = type.inside[0].to_s
                is_array = true
              else
                data_type = type.to_s
              end
              data_type = @context.get_or_infer_type(data_type)
              data_type.assert_size_on(version, size == 0 ? nil : size)
            end
            @buffers[index] = Buffer.new(data_type, tx_type, size, is_array)
          when "InRaw" # <size, alignment, position>
            size = SwIPC::parse_int(info.inside[0])
            alignment = SwIPC::parse_int(info.inside[1])
            position = SwIPC::parse_int(info.inside[2])
            data_type = nil
            if type then
              data_type = @context.get_or_infer_type(type.to_s)
              data_type.assert_size_on(version, size)
            end
            @inargs.push(Arg.new(size, alignment, position, data_type))
            @inargs.sort_by! do |a| a.position end
          when "OutRaw"
            size = SwIPC::parse_int(info.inside[0])
            alignment = SwIPC::parse_int(info.inside[1])
            position = SwIPC::parse_int(info.inside[2])
            if type then
              if type.before != "Out" then
                raise "invalid OutRaw type"
              end
              data_type = @context.get_or_infer_type(type.inside[0].to_s)
              data_type.assert_size_on(version, size)
            end
            @outargs.push(Arg.new(size, alignment, position, data_type))
            @outargs.sort_by! do |a| a.position end
          when "InObject"
            if_type = nil
            if type then
              if type.before != "SharedPointer" then
                raise "invalid InObject type"
              end
              if_type = type.inside[0].to_s
            end
            @ininterfaces[SwIPC::parse_int(info.inside[0])]||= if_type
          when "OutObject"
            of_type = nil
            if type then
              if type.before != "Out" then
                raise "invalid OutObject type: " + type.to_s
              end
              if type.inside[0].before != "SharedPointer" then
                raise "invalid OutObject type: " + type.to_s
              end
              of_type = type.inside[0].inside[0].to_s
            end
            @outinterfaces[SwIPC::parse_int(info.inside[0])]||= of_type
          when "InHandle"
            # type is uninteresting
            @inhandles[SwIPC::parse_int(info.inside[0])] = SwIPC::parse_int(info.inside[1])
          when "OutHandle"
            # type is uninteresting
            @outhandles[SwIPC::parse_int(info.inside[0])] = SwIPC::parse_int(info.inside[1])
          else
            raise "invalid info type: " + info.before
          end
        else
          # TODO: infer?
        end
      end
    end
    
    def can_merge?(other)
      if other.id != @id then
        return false
      end
      if other.name != nil && @name != nil && other.name != @name then
        return false
      end
      if other.buffers != nil && @buffers != nil then
        if other.buffers.length != @buffers.length then
          return false
        end
        @buffers.zip(other.buffers).each do |e|
          if e[0] == nil || e[1] == nil then
            return false
          end
          if !e[0].can_merge?(e[1]) then
            return false
          end
        end
      end
      if other.inargs != nil && @inargs != nil then
        if other.inargs.length != @inargs.length then
          return false
        end
        @inargs.zip(other.inargs).each do |e|
          if e[0] == nil || e[1] == nil then
            return false
          end
          if !e[0].can_merge?(e[1]) then
            return false
          end
        end
      end
      if other.outargs != nil && @outargs != nil then
        if other.outargs.length != @outargs.length then
          return false
        end
        @outargs.zip(other.outargs).each do |e|
          if e[0] == nil || e[1] == nil then
            return false
          end
          if !e[0].can_merge?(e[1]) then
            return false
          end
        end
      end
      if other.pid != nil && @pid != nil && other.pid != @pid then
        return false
      end
      if other.inbytes != nil && @inbytes != nil && other.inbytes != @inbytes then
        return false
      end
      if other.outbytes != nil && @outbytes != nil && other.outbytes != @outbytes then
        return false
      end
      if other.ininterfaces != nil && @ininterfaces != nil then
        if other.ininterfaces.length != @ininterfaces.length then
          return false
        end
        @ininterfaces.zip(other.ininterfaces).each do |e|
          if e[0] != e[1] then
            return false
          end
        end
      end
      if other.outinterfaces != nil && @outinterfaces != nil then
        if other.outinterfaces.length != @outinterfaces.length then
          return false
        end
        @outinterfaces.zip(other.outinterfaces).each do |e|
          if e[0] != nil && e[1] != nil && e[0] != e[1] then
            return false
          end
        end
      end
      if other.inhandles != nil && @inhandles != nil && other.inhandles != @inhandles then
        return false
      end
      if other.outhandles != nil && @outhandles != nil && other.outhandles != @outhandles then
        return false
      end
      return true
    end

    def merge!(other)
      SwIPC::merge_prop!(self, other, :@name)
      if @buffers == nil then
        if other.buffers != nil then
          @buffers = other.buffers
        end
      else
        if other.buffers != nil then
          @buffers.zip(other.buffers).map do |a, b|
            a.merge!(b)
          end
        end
      end
      if @inargs == nil then
        if other.inargs != nil then
          @inargs = other.inargs
        end
      else
        if other.inargs != nil then
          @inargs.zip(other.inargs).map do |a, b|
            a.merge!(b)
          end
        end
      end
      if @outargs == nil then
        if other.outargs != nil then
          @outargs = other.outargs
        end
      else
        if other.outargs != nil then
          @outargs.zip(other.outargs).map do |a, b|
            a.merge!(b)
          end
        end
      end
      SwIPC::merge_prop!(self, other, :@pid)
      SwIPC::merge_prop!(self, other, :@inbytes)
      SwIPC::merge_prop!(self, other, :@outbytes)
      @ininterfaces = merge_arr(@ininterfaces, other.ininterfaces)
      @outinterfaces = merge_arr(@outinterfaces, other.outinterfaces)
      SwIPC::merge_prop!(self, other, :@inhandles)
      SwIPC::merge_prop!(self, other, :@outhandles)
      @args_raw|= other.args_raw
      @sources = @sources.concat(other.sources)
    end

    def validate
      if @inargs then
        pos = 0
        @inargs.each do |a|
          pos = pos + (a.alignment - 1)
          pos = pos - (pos % a.alignment)
          if a.position != pos then
            raise "expected #{a.inspect} to be at #{pos}"
          end
          pos = pos + a.size
        end
        if pos != @inbytes then
          raise "total inbytes (#{inbytes}) did not match calculated #{pos}"
        end
      end
      if @outargs then
        pos = 0
        @outargs.each do |a|
          pos = pos + (a.alignment - 1)
          pos = pos - (pos % a.alignment)
          if a.position != pos then
            raise "expected #{a.inspect} to be at #{pos}"
          end
          pos = pos + a.size
        end
        if pos != @outbytes then
          raise "total outbytes (#{outbytes}) did not match calculated #{pos}"
        end
      end
    end
    
    def name_or_placeholder
      @name || "Unknown#{id}"
    end

    def buffer_to_swipc(b)
      return "buffer<#{b.join(", ")}>"
    end
    
    def to_swipc
      input = []
      output = []
      if @inargs != nil then
        @inargs.each do |a|
          input.push(a.to_swipc)
        end
      else
        if @inbytes == nil then
          input.push("unknown")
        elsif @inbytes > 0 then
          input.push("unknown<0x#{@inbytes.to_s(16)}>")
        end
      end
      if @outargs != nil then
        @outargs.each do |a|
          output.push(a.to_swipc)
        end
      else
        if @outbytes == nil then
          output.push("unknown")
        elsif @outbytes > 0 then
          output.push("unknown<0x#{@outbytes.to_s(16)}>")
        end
      end
      if @pid then
        input.push("pid")
      end
      if @inhandles then
        inhandles.each do |ih|
          case ih
          when 1
            input.push("KHandle<copy>")
          when 2
            input.push("KHandle<move>")
          else
            raise "invalid input handle: " + ih.to_s
          end
        end
      end
      if @outhandles then
        outhandles.each do |oh|
          case oh
          when 1
            output.push("KHandle<copy>")
          when 2
            output.push("KHandle<move>")
          else
            raise "invalid output handle: " + oh.to_s
          end
        end
      end
      if @buffers then
        @buffers.each do |b|
          if (b.transfer_type & 1) > 0 then
            input.push(b.to_swipc)
          else
            output.push(b.to_swipc)
          end
        end
      end
      if @ininterfaces then
        @ininterfaces.each do |i|
          input.push("object<#{i || "unknown"}>")
        end
      end
      if @outinterfaces then
        @outinterfaces.each do |i|
          output.push("object<#{i || "unknown"}>")
        end
      end
      
      # build string
      str = "[#{id}] #{name_or_placeholder}(" +
            input.join(", ") +
            ")"
      
      if output.length > 1 then
        str = str + " -> (" + output.join(", ") + ")"
      elsif output.length == 1 then
        str = str + " -> " + output[0]
      end
      str = str + ";"
    end

    class Arg
      def initialize(size, alignment, position, data_type)
        @size = size
        @alignment = alignment
        @position = position
        @data_type = data_type
      end
      
      attr_reader :size
      attr_reader :alignment
      attr_reader :position
      attr_reader :data_type
      
      def can_merge?(other)
        if @size != other.size then
          return false
        end
        if @alignment != other.alignment then
          return false
        end
        if @position != other.position then
          return false
        end
        if @data_type != nil && other.data_type != nil && @data_type != other.data_type then
          return false
        end
        return true
      end
      
      def merge!(other)
        SwIPC::merge_prop!(self, other, :@size)
        SwIPC::merge_prop!(self, other, :@alignment)
        SwIPC::merge_prop!(self, other, :@position)
        SwIPC::merge_prop!(self, other, :@data_type)
      end
      
      def to_swipc
        return @data_type ? @data_type.name : "unknown<0x#{@size.to_s(16)}>"
      end
    end
    
    private
    def merge_arr(a, b)
      if a == nil then return b end
      if b == nil then return a end
      if a.length != b.length then
        raise "can't merge lists of different lengths"
      end
      return a.zip(b).map do |z|
        if z[0] != nil && z[1] != nil && z[0] != z[1] then
          raise "can't merge #{z[0]} and #{z[1]}"
        end
        next z[0] || z[1]
      end
    end  
  end
end
