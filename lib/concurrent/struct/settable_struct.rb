require 'concurrent/struct/abstract_struct'
require 'concurrent/errors'
require 'concurrent/synchronization'

module Concurrent

  # An thread-safe, write-once variation of Ruby's standard `Struct`.
  # Each member can have its value set at most once, either at construction
  # or any time thereafter. Attempting to assign a value to a member
  # that has already been set will result in a `Concurrent::ImmutabilityError`.
  #
  # @see http://ruby-doc.org/core-2.2.0/Struct.html Ruby standard library `Struct`
  # @see http://en.wikipedia.org/wiki/Final_(Java) Java `final` keyword
  module SettableStruct
    include AbstractStruct

    # @!macro struct_values
    def values
      synchronize { ns_values }
    end
    alias_method :to_a, :values

    # @!macro struct_values_at
    def values_at(*indexes)
      synchronize { ns_values_at(indexes) }
    end

    # @!macro struct_inspect
    def inspect
      synchronize { ns_inspect }
    end
    alias_method :to_s, :inspect

    # @!macro struct_merge
    def merge(other, &block)
      synchronize { ns_merge(other, &block) }
    end

    # @!macro struct_to_h
    def to_h
      synchronize { ns_to_h }
    end

    # @!macro struct_get
    def [](member)
      synchronize { ns_get(member) }
    end

    # @!macro struct_equality
    def ==(other)
      synchronize { ns_equality(other) }
    end

    # @!macro struct_each
    def each(&block)
      return enum_for(:each) unless block_given?
      synchronize { ns_each(&block) }
    end

    # @!macro struct_each_pair
    def each_pair(&block)
      return enum_for(:each_pair) unless block_given?
      synchronize { ns_each_pair(&block) }
    end

    # @!macro struct_select
    def select(&block)
      return enum_for(:select) unless block_given?
      synchronize { ns_select(&block) }
    end

    # @!macro struct_set
    #
    # @raise [Concurrent::ImmutabilityError] if the given member has already been set
    def []=(member, value)
      if member.is_a? Integer
        if member >= @values.length
          raise IndexError.new("offset #{member} too large for struct(size:#{@values.length})")
        end
        synchronize do
          unless @values[member].nil?
            raise Concurrent::ImmutabilityError.new('struct member has already been set')
          end
          @values[member] = value
        end
      else
        send("#{member}=", value)
      end
    rescue NoMethodError
      raise NameError.new("no member '#{member}' in struct")
    end

    # @!macro struct_new
    def self.new(*args, &block)
      clazz_name = nil
      if args.length == 0
        raise ArgumentError.new('wrong number of arguments (0 for 1+)')
      elsif args.length > 0 && args.first.is_a?(String)
        clazz_name = args.shift
      end
      FACTORY.define_struct(clazz_name, args, &block)
    end

    FACTORY = Class.new(Synchronization::Object) do
      def define_struct(name, members, &block)
        synchronize do
          clazz = AbstractStruct.define_struct_class(SettableStruct, Synchronization::Object, name, members, &block)
          members.each_with_index do |member, index|
            clazz.send(:define_method, member) do
              synchronize { @values[index] }
            end
            clazz.send(:define_method, "#{member}=") do |value|
              synchronize do
                unless @values[index].nil?
                  raise Concurrent::ImmutabilityError.new('struct member has already been set')
                end
                @values[index] = value
              end
            end
          end
          clazz
        end
      end
    end.new
    private_constant :FACTORY
  end
end
