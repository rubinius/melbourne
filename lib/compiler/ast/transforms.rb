# -*- encoding: us-ascii -*-

module Rubinius
  module AST
    module Transforms
      def self.register(category, name, klass)
        transform_map[name] = klass
        category_map[category] << klass
      end

      def self.transform_map
        @transform_map ||= { }
      end

      def self.category_map
        @category_map ||= Hash.new { |h, k| h[k] = [] }
      end

      def self.[](name)
        transform_map[name]
      end

      def self.category(name)
        if name == :all
          category_map.values.flatten
        else
          category_map[name]
        end
      end
    end

    ##
    # Handles block_given?
    class BlockGiven < Send
      transform :default, :block_given, "VM instruction for block_given?, iterator?"

      def self.match?(line, receiver, name, arguments, privately)
        if receiver.kind_of? Self and (name == :block_given? or name == :iterator?)
          new line, receiver, name, privately
        end
      end
    end

    class AccessUndefined < Send
      transform :kernel, :access_undefined, "VM instruction for undefined"

      def self.match?(line, receiver, name, arguments, privately)
        if privately and name == :undefined
          new line, receiver, name, privately
        end
      end
    end

    ##
    # Handles Rubinius.primitive
    class SendPrimitive < SendWithArguments
      transform :default, :primitive, "Rubinius.primitive"

      def self.match?(line, receiver, name, arguments, privately)
        match_send? receiver, :Rubinius, name, :primitive
      end
    end

    ##
    # Handles Rubinius.check_frozen
    class CheckFrozen < SendWithArguments
      transform :default, :frozen, "Rubinius.check_frozen"

      def self.match?(line, receiver, name, arguments, privately)
        match_send? receiver, :Rubinius, name, :check_frozen
      end
    end

    ##
    # Handles Rubinius.invoke_primitive
    #
    class InvokePrimitive < SendWithArguments
      transform :default, :invoke_primitive, "Rubinius.invoke_primitive"

      def self.match?(line, receiver, name, arguments, privately)
        match_send? receiver, :Rubinius, name, :invoke_primitive
      end
    end

    ##
    # Handles Rubinius.call_custom
    #
    class CallCustom < SendWithArguments
      transform :default, :call_custom, "Rubinius.call_custom"

      def self.match?(line, receiver, name, arguments, privately)
        match_send? receiver, :Rubinius, name, :call_custom
      end
    end

    ##
    # Handles Rubinius.single_block_arg
    #
    # Given the following code:
    #
    #   m { |x| ... }
    #
    # In Ruby 1.8, this has the following semantics:
    #
    #   * x == nil if no values are yielded
    #   * x == val if one value is yielded
    #   * x == [p, q, r, ...] if more than one value is yielded
    #   * x == [a, b, c, ...] if one Array is yielded
    #
    # In Ruby 1.9, this has the following semantics:
    #
    #   * x == nil if no values are yielded
    #   * x == val if one value is yielded
    #   * x == p if yield(p, q, r, ...)
    #   * x == [a, b, c, ...] if one Array is yielded
    #
    # However, in Ruby 1.9, the Enumerator code manually implements the 1.8
    # block argument semantics. This transform exposes the VM instruction we
    # use in 1.8 mode (cast_for_single_block_arg) so we can use it in 1.9 mode
    # for Enumerator.
    #
    class SingleBlockArg < SendWithArguments
      transform :default, :single_block_arg, "Rubinius.single_block_arg"

      def self.match?(line, receiver, name, arguments, privately)
        match_send? receiver, :Rubinius, name, :single_block_arg
      end
    end

    ##
    # Handles Rubinius.asm
    #
    class InlineAssembly < SendWithArguments
      transform :default, :assembly, "Rubinius.asm"

      def self.match?(line, receiver, name, arguments, privately)
        match_send? receiver, :Rubinius, name, :asm
      end
    end

    ##
    # Handles Rubinius.privately
    #
    class SendPrivately < Send
      transform :kernel, :privately, "Rubinius.privately"

      def self.match?(line, receiver, name, arguments, privately)
        if match_send? receiver, :Rubinius, name, :privately
          new line, receiver, name, privately
        end
      end

      def block=(iter)
        @block = iter.body
      end

      def map_sends
        walk do |result, node|
          case node
          when Send, SendWithArguments
            node.privately = true
          end

          result
        end
      end
    end

    ##
    # Emits fast VM instructions for certain methods.
    #
    class SendFastMath < SendWithArguments
      transform :default, :fast_math, "VM instructions for math, relational methods"

      Operators = {
        :+    => :meta_send_op_plus,
        :-    => :meta_send_op_minus,
        :==   => :meta_send_op_equal,
        :===  => :meta_send_op_tequal,
        :<    => :meta_send_op_lt,
        :>    => :meta_send_op_gt
      }

      def self.match?(line, receiver, name, arguments, privately)
        return false unless op = Operators[name]
        if match_arguments? arguments, 1
          node = new line, receiver, name, arguments
          node.operator = op
          node
        end
      end

      attr_accessor :operator
    end

    ##
    # Emits a fast path for #new
    #
    class SendFastNew < SendWithArguments
      transform :default, :fast_new, "Fast SomeClass.new path"

      # FIXME duplicated from kernel/common/compiled_code.rb
      KernelMethodSerial = 47

      def self.match?(line, receiver, name, arguments, privately)
        # ignore vcall style
        return false if !arguments and privately
        name == :new
      end
    end

    ##
    # Emits "safe" names for certain fundamental core library methods
    #
    class SendKernelMethod < SendWithArguments
      transform :kernel, :kernel_methods, "Safe names for fundamental methods"

      Methods = {
        :/      => :divide,
        :__slash__ => :/,
        :class  => :__class__
      }

      Arguments = {
        :/      => 1,
        :__slash__ => 1,
        :class  => 0
      }

      def self.match?(line, receiver, name, arguments, privately)
        return false unless rename = Methods[name]
        if match_arguments? arguments, Arguments[name]
          new line, receiver, rename, arguments, privately
        end
      end
    end

    ##
    # Maps various methods to VM instructions
    #
    class SendInstructionMethod < SendWithArguments
      transform :default, :fast_system, "VM instructions for certain methods"

      Methods = {
        :__kind_of__     => :kind_of,
        :__instance_of__ => :instance_of,
        :__nil__         => :is_nil,
      }

      Arguments = {
        :__kind_of__     => 1,
        :__instance_of__ => 1,
        :__nil__         => 0,
      }

      def self.match?(line, receiver, name, arguments, privately)
        return false unless rename = Methods[name]
        if match_arguments? arguments, Arguments[name]
          new line, receiver, rename, arguments, privately
        end
      end
    end

    ##
    # Speeds up certain forms of Type.coerce_to
    #
    class SendFastCoerceTo < SendWithArguments
      transform :default, :fast_coerce, "Fast Rubinius::Type.coerce_to path"

      def self.match?(line, receiver, name, arguments, privately)
        methods = [:coerce_to, :check_convert_type, :try_convert]
        receiver.kind_of?(TypeConstant) && methods.include?(name) &&
          arguments.body.size == 3
      end
    end

    ##
    # Handles loop do ... end
    #
    class SendLoop < Send
      transform :magic, :loop, "loop do ... end"

      def self.match?(line, receiver, name, arguments, privately)
        if receiver.kind_of? Self and name == :loop
          new line, receiver, name, privately
        end
      end

      def block=(iter)
        if iter.kind_of? BlockPass
          @blockarg = iter
        else
          @block = iter.body
        end
      end
    end
  end
end
