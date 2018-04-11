require "json"

require_relative "util.rb"
require_relative "data_source.rb"
require_relative "types.rb"
require_relative "buffer.rb"
require_relative "interface.rb"
require_relative "command.rb"
require_relative "context.rb"

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

def parseServerData(context, version, path)
  data = JSON.parse(File.read(path))
  data.each_pair do |mod, data|
    source = SwIPC::DataSource.new(version, "server-" + mod)
    data.each_pair do |interface_name, interface_commands|
      if interface_name == "nns::hosbinder::IHOSBinderDriver" then next end
      i = context.get_or_create_interface(interface_name)
      i.exists_on(version)
      interface_commands.each_pair do |id, desc|
        begin
          command = SwIPC::Command.new(context, id.to_i, source)
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

def parseClientData(context, version, path, desc)
  source = SwIPC::DataSource.new(version, "client-" + desc)
  data = JSON.parse(File.read(path))
  data.each_pair do |interface_name, interface_commands|
    if interface_name == "nns::hosbinder::IHOSBinderDriver" then next end
    i = context.get_or_create_interface(interface_name)
    i.exists_on(version)
    interface_commands.each_pair do |id, desc|
      command = SwIPC::Command.new(context, id.to_i, source)
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

context = SwIPC::Context.new
parseServerData(context, "1.0.0", "auto/newdata/server/data1.json")
parseClientData(context, "1.0.0", "auto/newdata/client/data1.json", "0.16.29-from-flog")
parseServerData(context, "2.0.0", "auto/newdata/server/data2.json")
parseClientData(context, "2.0.0", "auto/newdata/client/data2.json", "1.3.1-from-BoTW120-nnSdk-1_3_1-Release")
parseServerData(context, "3.0.0", "auto/newdata/server/data3.json")
parseClientData(context, "3.0.0", "auto/newdata/client/data3.json", "3.5.1-from-Odyssey-nnSdk-3_5_1-Release")
parseServerData(context, "4.0.0", "auto/newdata/server/data4.json")
parseClientData(context, "4.0.0", "auto/newdata/client/data4.json", "4.4.0-from-Hulu")

context.types.sort_by do |t|
  [t.versions.min, t.versions.max, t.name.to_s]
end.each do |t|
  if t.should_emit? then
    puts t.to_swipc
  end
end

puts ""

puts(context.interfaces.sort_by do |i|
       i.name
     end.map do |i|
       i.to_swipc
     end.join("\n"))
