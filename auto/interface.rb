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
      @commands[command.id] = CommandGroup.new(self)
    end
    entry = @commands[command.id]
    entry.append(version, command)
  end

  def to_swipc
    out = ""
    if SwIPC::needs_version_decorator?(@versions) then
      out<<= SwIPC::generate_version_decorator(@versions) + "\n"
    end
    out<<= "interface #{name} {\n"
    
    @commands.keys.sort.each do |id|
      out<<= @commands[id].to_swipc(@versions).lines.map do |l|
        "\t" + l
      end.join + "\n"
    end
    
    out<<= "}\n"
  end

  # represents a group of command definitions that all share one ID
  class CommandGroup
    def initialize(interface)
      @interface = interface
      @versions = []
    end

    class CommandEntry
      def initialize(command, versions)
        @command = command
        @versions = versions
      end
      attr_accessor :command
      attr_accessor :versions
    end
    
    def append(version, command)
      v = version.split(".").map do |i| i.to_i end
      if @latest_version && ((v <=> @latest_version) < 0) then
        raise "add command entries in version order please"
      end
      if @latest && @latest.command.can_merge?(command) then
        @latest.command.merge!(command)
        if !@latest.versions.include?(version) then
          @latest.versions.push(version)
        end
      else
        if @latest_version && @latest_version == v then
          puts "can't merge two commands from same version #{v} for #{@interface.name}##{command.id}:"
          puts "  " + @latest.command.inspect
          puts "  " + command.inspect
          raise "failure"
        end
        e = CommandEntry.new(command, [version])
        @versions.push(e)
        @latest = e
        @latest_version = v
      end
    end

    def to_swipc(version_scope=ALL_VERSIONS)
      @versions.map do |v|
        out = ""
        if SwIPC::needs_version_decorator?(v.versions, version_scope) then
          out<<= SwIPC::generate_version_decorator(v.versions, version_scope) + "\n"
        end
        out<<= v.command.to_swipc
        next out
      end.join("\n")
    end
  end
end
