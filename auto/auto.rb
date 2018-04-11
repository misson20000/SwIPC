require "json"

def parse_int(str)
  str = str.strip
  if str.match(/0x[A-Fa-f0-9]+/) then
    return str.to_i(16)
  elsif str.match(/[0-9]+/) then
    return str.to_i(10)
  else
    raise "invalid int: " + str
  end
end

def merge_prop!(a, b, prop)
  aval = a.instance_variable_get(prop)
  bval = b.instance_variable_get(prop)
  if aval == nil then
    a.instance_variable_set(prop, bval)
  else
    if bval != nil then
      if aval != bval then
        raise "can't merge #{prop} with different values: #{aval} and #{bval}"
      else
        a.instance_variable_set(prop, bval)
      end
    end
  end
end

ALL_VERSIONS = ["1.0.0", "2.0.0", "3.0.0", "4.0.0"]
def needs_version_decorator?(versions, version_scope=ALL_VERSIONS)
  return versions.first != version_scope.first || versions.last != version_scope.last
end

def generate_version_decorator(versions, version_scope=ALL_VERSIONS)
  if versions.first == version_scope.first && versions.last == version_scope.last then
    return nil
  end
  if versions.last == "4.0.0" then
    return "@version(#{versions.first}+)"
  elsif versions.first == versions.last then
    return "@version(#{versions.first})"
  else
    return "@version(#{versions.first}-#{versions.last})"
  end
end

class StaticType
  def initialize(name, size, prefix)
    @name = name
    @size = size
    @prefix = prefix
  end

  def name
    @prefix + (@size * 8).to_s
  end
  
  attr_reader :size

  def is_static?
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

  def emit_swipc
    # don't emit
  end
end

class Type
  def initialize(name)
    @name = name
    @sizes = Hash.new
  end

  attr_reader :name
  attr_reader :sizes

  def is_static?
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
  
  def emit_swipc
    @sizes.keys.group_by do |v|
      @sizes[v]
    end.each_pair do |size, versions|
      if needs_version_decorator?(versions, VERSION_SCOPE) then
        puts generate_version_decorator(versions, VERSION_SCOPE)
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
      puts "type #{name} = #{szstr};"
    end
  end
  
  class << self
    def get(name)
      @mapping||= {}
      if !@mapping[name] then
        @mapping[name] = Type.new(name)
      end
      return @mapping[name]
    end

    def static_int(name, size)
      @mapping||= {}
      {"signed " => "s", "unsigned " => "u", "" => "u"}.each_pair do |prefix, c|
        @mapping[prefix + name] = StaticType.new(prefix + name, size, c)
      end
    end

    def static(name, size, c)
      @mapping||= {}
      @mapping[name] = StaticType.new(name, size, c)
    end
    
    def list
      return @mapping.values
    end
  end
end

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
    merge_prop!(self, other, :@data_type)
    merge_prop!(self, other, :@transfer_type)
    merge_prop!(self, other, :@size)
    merge_prop!(self, other, :@is_array)
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
    merge_prop!(self, other, :@size)
    merge_prop!(self, other, :@alignment)
    merge_prop!(self, other, :@position)
    merge_prop!(self, other, :@data_type)
  end

  def to_swipc
    return @data_type ? @data_type.name : "unknown<0x#{@size.to_s(16)}>"
  end
end

def repack(arr)
  if arr.is_a? String then
    return arr
  end
  str = arr[0]
  if arr[1] then
    str = str + "<" + (arr[1].is_a?(String) ? arr[1] : arr[1].join(", ")) + ">"
  end
  if arr[2] then
    str = str + arr[2]
  end
  return str
end

class Command
  def initialize(id, source)
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
    "##{id}: #{name}, buffers: [#{buffers.join(", ")}], pid: #{pid}, inbytes: #{inbytes}, outbytes: #{outbytes}, ininterfaces: #{ininterfaces}, outinterfaces: #{outinterfaces}, inhandles: #{inhandles}, outhandles: #{outhandles}"
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
          index = parse_int(info.inside[0])
          tx_type = parse_int(info.inside[1])
          size = parse_int(info.inside[2])
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
            data_type = Type.get(data_type)
            data_type.assert_size_on(version, size == 0 ? nil : size)
          end
          @buffers[index] = Buffer.new(data_type, tx_type, size, is_array)
        when "InRaw" # <size, alignment, position>
          size = parse_int(info.inside[0])
          alignment = parse_int(info.inside[1])
          position = parse_int(info.inside[2])
          data_type = nil
          if type then
            data_type = Type.get(type.to_s)
            data_type.assert_size_on(version, size)
          end
          @inargs.push(Arg.new(size, alignment, position, data_type))
          @inargs.sort_by! do |a| a.position end
        when "OutRaw"
          size = parse_int(info.inside[0])
          alignment = parse_int(info.inside[1])
          position = parse_int(info.inside[2])
          if type then
            if type.before != "Out" then
              raise "invalid OutRaw type"
            end
            data_type = Type.get(type.inside[0].to_s)
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
          @ininterfaces[parse_int(info.inside[0])]||= if_type
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
          @outinterfaces[parse_int(info.inside[0])]||= of_type
        when "InHandle"
          # type is uninteresting
          @inhandles[parse_int(info.inside[0])] = parse_int(info.inside[1])
        when "OutHandle"
          # type is uninteresting
          @outhandles[parse_int(info.inside[0])] = parse_int(info.inside[1])
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
    merge_prop!(self, other, :@name)
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
    merge_prop!(self, other, :@pid)
    merge_prop!(self, other, :@inbytes)
    merge_prop!(self, other, :@outbytes)
    @ininterfaces = merge_arr(@ininterfaces, other.ininterfaces)
    @outinterfaces = merge_arr(@outinterfaces, other.outinterfaces)
    merge_prop!(self, other, :@inhandles)
    merge_prop!(self, other, :@outhandles)
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

class CommandEntry
  def initialize(interface)
    @interface = interface
    @latest_version = nil
    @latest = nil
    @versions = []
  end

  def append(version, command)
    v = version.split(".").map do |i| i.to_i end
    if @latest_version && ((v <=> @latest_version) < 0) then
      raise "add command entries in version order please"
    end
    if @latest && @latest[0].can_merge?(command) then
      @latest[0].merge!(command)
      if !@latest[1].include?(version) then
        @latest[1].push(version)
      end
    else
      if @latest_version && @latest_version == v then
        puts "can't merge two commands from same version #{v} for #{@interface.name}##{command.id}:"
        puts "  " + @latest[0].inspect
        puts "  " + command.inspect
        raise "failure"
      end
      e = [command, [version]]
      @versions.push(e)
      @latest = e
      @latest_version = v
    end
  end

  def dump
    @versions.each do |v|
      puts "    @{#{v[1]}}"
      puts "      " + v[0].inspect
    end
  end

  def emit_swipc(version_scope=ALL_VERSIONS)
    @versions.each do |v|
      if v[1].first != "1.0.0" || v[1].last != "4.0.0" then
        version_string = v[1].first
        if v[1].length > 1 then
          if v[1].last == "4.0.0" then
            version_string = v[1].first + "+"
          else
            version_string = v[1].first + "-" + v[1].last
          end
        end
        if needs_version_decorator?(v[1], version_scope) then
          puts "\t" + generate_version_decorator(v[1], version_scope)
        end
      end
      puts "\t" + v[0].to_swipc
    end
  end
end

class Interface
  def initialize(name, registration=nil)
    @name = name
    @registration = registration
    @versions = []
    @commands = Hash.new
  end

  attr_reader :name
  
  def exists_on(version)
    @versions.push(version)
  end

  def append_command(version, command)
    if !@commands[command.id] then
      @commands[command.id] = CommandEntry.new(self)
    end
    entry = @commands[command.id]
    entry.append(version, command)
  end

  def dump
    puts name
    @commands.each_pair do |id, e|
      puts "  ##{id}:"
      e.dump
    end
  end

  def emit_swipc
    if needs_version_decorator?(@versions) then
      puts generate_version_decorator(@versions)
    end
    puts "interface #{name} {"
    
    @commands.keys.sort.each do |id|
      @commands[id].emit_swipc(@versions)
    end
    
    puts "}"
    puts ""
  end
  
  class << self
    def get(name)
      @mapping||= {}
      if !@mapping[name] then
        @mapping[name] = Interface.new(name)
      end
      return @mapping[name]
    end

    def list
      return @mapping.values
    end
  end
end

class DataSource
  def initialize(version, desc)
    @version = version
    @desc = desc
  end

  def to_s
    "#{@desc}@#{@version}"
  end
end

class TemplateAST
  def initialize(before, inside, after)
    @before = before.match(/\A(.*?)(?: *const\&)?\z/)[1]
    @inside = inside
    @after = after.match(/\A(.*?)(?: *const\&)?\z/)[1]
  end

  def to_s
    return @before + (@inside ? "<" + (@inside.map do |e| e.to_s end).join(", ") + ">" : "" ) + (@after == "" ? "" : " " + @after)
  end
  
  def self.parse_single(e, force_template_ast=false)
    if e.is_a?(String) then
      e = e.each_char
    end

    before = ""
    inside = nil
    after = ""
    begin
      while e.peek != "<" && e.peek != "," && e.peek != ">" && e.peek != " " do
        before = before + e.next
      end
      if e.peek == "<" || e.peek == " " then
        if e.peek == "<" then
          e.next # skip <
          inside = parse_list(e)
          if e.peek == ">" then
            e.next # skip >
          else
            raise "invalid state"
          end
        end
        while e.peek == " " do e.next end # swallow spaces
        after = ""
        begin
          while e.peek != "<" && e.peek != "," && e.peek != ">" do
            after = after + e.next
          end
        rescue StopIteration
        end
        return self.new(before, inside, after)
      elsif e.peek == "," then
        return force_template_ast ? TemplateAST.new(before, inside, after) : before
      elsif e.peek == ">" then
        return force_template_ast ? TemplateAST.new(before, inside, after) : before
      else
        raise "invalid state"
      end
    rescue StopIteration
    end
    return force_template_ast ? TemplateAST.new(before, inside, after) : before
  end

  def self.parse_list(e, force_template_ast=false)
    if e.is_a?(String) then
      e = e.each_char
    end
    
    arr = []
    begin
      loop do
        while e.peek == " " do e.next end
        s = parse_single(e, force_template_ast)
        arr.push(s)
        if e.peek == "," then
          e.next
        elsif e.peek == ">" then
          return arr
        else
          raise "invalid state: head left at #{e.peek}"
        end
      end
    rescue StopIteration
      return arr
    end
    return arr
  end
  
  attr_reader :before
  attr_reader :inside
  attr_reader :after
end

def parseServerData(version, path)
  data = JSON.parse(File.read(path))
  data.each_pair do |mod, data|
    source = DataSource.new(version, "server-" + mod)
    data.each_pair do |interface_name, interface_commands|
      if interface_name == "nns::hosbinder::IHOSBinderDriver" then next end
      i = Interface.get(interface_name)
      i.exists_on(version)
      interface_commands.each_pair do |id, desc|
        begin
          command = Command.new(id.to_i, source)
          command.add_data("buffers", [])
          command.add_data("pid", false)
          command.add_data("inhandles", [])
          command.add_data("outhandles", [])
          command.add_data("ininterfaces", [])
          command.add_data("outinterfaces", [])
          desc.each_pair do |key, value|
            command.add_data(key, value)
          end
          command.validate
          i.append_command(version, command)
        rescue => e
          puts "on #{interface_name}##{id}: " + desc.inspect
          throw e
        end
      end
    end
  end
end

def parseClientData(version, path, desc)
  source = DataSource.new(version, "client-" + desc)
  data = JSON.parse(File.read(path))
  data.each_pair do |interface_name, interface_commands|
    if interface_name == "nns::hosbinder::IHOSBinderDriver" then next end
    i = Interface.get(interface_name)
    i.exists_on(version)
    interface_commands.each_pair do |id, desc|
      command = Command.new(id.to_i, source)
      desc.each_pair do |key, value|
        if key == "args" || key == "arginfo" then next end
        command.add_data(key, value)
      end
      args = TemplateAST.parse_list(desc["args"] || "", true)
      arginfo = TemplateAST.parse_list(desc["arginfo"] || "", true)
      args.fill(nil, args.length...arginfo.length)
      command.add_args(args.zip(arginfo), desc["args"] != nil, desc["arginfo"] != nil, version)
      command.validate
      i.append_command(version, command)
    end
  end
end

Type.static_int("char", 1)
Type.static_int("short", 2)
Type.static_int("int", 4)
Type.static_int("long", 8)
Type.static("float", 4, "f")
Type.static("bool", 1, "b")

parseServerData("1.0.0", "auto/newdata/server/data1.json")
parseClientData("1.0.0", "auto/newdata/client/data1.json", "0.16.29-from-flog")
parseServerData("2.0.0", "auto/newdata/server/data2.json")
parseClientData("2.0.0", "auto/newdata/client/data2.json", "1.3.1-from-BoTW120-nnSdk-1_3_1-Release")
parseServerData("3.0.0", "auto/newdata/server/data3.json")
parseClientData("3.0.0", "auto/newdata/client/data3.json", "3.5.1-from-Odyssey-nnSdk-3_5_1-Release")
parseServerData("4.0.0", "auto/newdata/server/data4.json")
parseClientData("4.0.0", "auto/newdata/client/data4.json", "4.4.0-from-Hulu")

Type.list.sort_by do |t|
  [t.versions.min, t.versions.max, t.name.to_s]
end.each do |t|
  t.emit_swipc
end

puts ""

Interface.list.sort_by do |i|
  i.name
end.each do |i|
  i.emit_swipc
end

Type.list.map do |t|
#  puts t.name.to_s + " = unknown<#{t.sizes}>"
end
