module SwIPC
  class Context
    def initialize
      @types = {}
      @interfaces = {}
      add_builtin_int_type("char", 1)
      add_builtin_int_type("short", 2)
      add_builtin_int_type("int", 4)
      add_builtin_int_type("long", 8)
      add_builtin_type("float", 4, "f")
      add_builtin_type("bool", 1, "b")
    end

    def get_or_create_interface(name)
      if !@interfaces[name] then
        @interfaces[name] = Interface.new(name)
      end
      return @interfaces[name]
    end

    def get_or_infer_type(name)
      if !@types[name] then
        @types[name] = InferredType.new(name)
      end
      return @types[name]
    end
    
    def types
      @types.values
    end

    def interfaces
      @interfaces.values
    end

    def add_builtin_int_type(name, size)
      {"signed " => "i", "unsigned " => "u", "" => "u"}.each_pair do |prefix, c|
        t = BuiltinType.new(prefix + name, size, c)
        @types[prefix + name] = t
        @types[t.name] = t
      end
    end

    def add_builtin_type(name, size, c)
      t = BuiltinType.new(name, size, c)
      @types[name] = t
      @types[t.name] = t
    end
  end
end
