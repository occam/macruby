module HotCocoa
  module Mappings
  
    def self.reload
      Dir.glob(File.join(File.dirname(__FILE__), "mappings", "*.rb")).each do |mapping|
        load mapping
      end
    end
    
    DefaultEmptyRect = [0,0,0,0]

    module TargetActionConvenience
      def on_action=(behavior)
        object = Object.new
        object.instance_variable_set("@behavior", behavior)
        def object.perform_action(sender)
          @behavior.call(sender)
        end
        setTarget(object)
        setAction("perform_action:")
      end
     
      def on_action(&behavior)
        self.on_action = behavior
        self
      end
    end
  
    def self.map(options, &block)
      framework = options.delete(:framework)
      mapped_name = options.keys.first
      mapped_value = options.values.first
      const = Object.full_const_get(mapped_value)
      if mapped_value.kind_of?(Class)
        m = Mapper.map_instances_of(mapped_value, mapped_name, &block)
        mappings[m.builder_method] = m
      elsif framework.nil? || const
        m = Mapper.map_instances_of(const, mapped_name, &block)
        mappings[m.builder_method] = m
      else
        on_framework(framework) do
          m = Mapper.map_instances_of(const, mapped_name, &block)
          mappings[m.builder_method] = m
        end
      end
    end
  
    def self.mappings
      @mappings ||= {}
    end
  
    def self.on_framework(name, &block)
      (frameworks[name.to_s.downcase] ||= []) << block
    end
  
    def self.frameworks
      @frameworks ||= {}
    end
  
    def self.framework_loaded(name)
      if frameworks[name.to_s.downcase]
        frameworks[name.to_s.downcase].each do |mapper|
          mapper.call
        end
      end
    end
    
  end
  
end
