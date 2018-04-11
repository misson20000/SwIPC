module SwIPC
  ALL_VERSIONS = ["1.0.0", "2.0.0", "3.0.0", "4.0.0"]

  class << self
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
  end
end
