require_relative "idparser"
require "pp"
pp SwIPC::Transform.new.apply(SwIPC::Parser.new.parse_with_debug(File.read("test.id")), :swipc_context => SwIPC::Context.new)
