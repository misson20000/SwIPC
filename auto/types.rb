module SwIPC
  class Type
    def should_emit?
      true
    end
    
    def to_swipc
      ""
    end
  end

  class BuiltinType < Type
    def initialize(name, size, prefix)
      @name = name
      @size = size
      @prefix = prefix
    end

    def name
      @prefix + (@size * 8).to_s
    end
    
    attr_reader :size

    def is_builtin?
      true
    end

    def versions
      ALL_VERSIONS
    end
    
    def size_on(version)
      @size
    end

    def sizes
      {:all => @size}
    end
    
    def assert_size_on(version, size)
      if size && size != @size then
        raise "static type #{name} of size #{@size} is not #{size}"
      end
    end

    def should_emit?
      false
    end
  end

  class InferredType < Type
    def initialize(name)
      @name = name
      @sizes = Hash.new
    end

    attr_reader :name
    attr_reader :sizes

    def is_builtin?
      false
    end

    def versions
      @sizes.keys
    end
    
    def size_on(version)
      @sizes[version]
    end
    
    def assert_size_on(version, size)
      if size && @sizes[version] && @sizes[version] != size then
        raise "type '#{@name}' on '#{version}' is already #{@sizes[version]} bytes long, not #{size} bytes"
      end
      @sizes[version] = size
      return self
    end

    VERSION_SCOPE = ALL_VERSIONS.drop(1) # no version information on 1.0.0
    
    def to_swipc
      @sizes.keys.group_by do |v|
        @sizes[v]
      end.each_pair.map do |size, versions|
        out = ""
        if SwIPC::needs_version_decorator?(versions, VERSION_SCOPE) then
          out<<= SwIPC::generate_version_decorator(versions, VERSION_SCOPE) + "\n"
        end
        szstr = ""
        case size
        when 1
          szstr = "i8"
        when 2
          szstr = "i16"
        when 4
          szstr = "i32"
        when 8
          szstr = "i64"
        when nil
          szstr = "unknown"
        else
          szstr = "bytes<0x#{size.to_s(16)}>"
        end
        out<<= "type #{name} = #{szstr};"
      end.join("\n")
    end  
  end

  class AliasedType < Type
    def initialize(name, other)
      @name = name
      @other = other
    end

    def is_builtin?
      false
    end

    def versions
    end
  end
end
