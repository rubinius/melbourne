# -*- encoding: us-ascii -*-

module Rubinius
  module AST
    class Send < Node
      attr_accessor :receiver, :name, :privately, :block, :variable
      attr_accessor :check_for_local

      def initialize(line, receiver, name, privately=false, vcall_style=false)
        @line = line
        @receiver = receiver
        @name = name
        @privately = privately
        @block = nil
        @check_for_local = false
        @vcall_style = vcall_style
      end

      def check_local_reference(g)
        if @receiver.kind_of? Self and (@check_for_local or g.state.eval?)
          g.state.scope.search_local(@name)
        end
      end

      def sexp_name
        :call
      end

      def receiver_sexp
        @privately ? nil : @receiver.to_sexp
      end

      def arguments_sexp
        return nil if @vcall_style

        sexp = [:arglist]
        sexp << @block.to_sexp if @block.kind_of? BlockPass
        sexp
      end

      def to_sexp
        sexp = [sexp_name, receiver_sexp, @name, arguments_sexp]
        case @block
        when For
          @block.to_sexp.insert 1, @receiver.to_sexp
        when Iter
          @block.to_sexp.insert 1, sexp
        else
          sexp
        end
      end
    end

    class SendWithArguments < Send
      attr_accessor :arguments

      def initialize(line, receiver, name, arguments, privately=false)
        super line, receiver, name, privately
        @block = nil
        @arguments = ActualArguments.new line, arguments
      end

      def arguments_sexp(name=:arglist)
        sexp = [name] + @arguments.to_sexp
        sexp << @block.to_sexp if @block
        sexp
      end
    end

    class AttributeAssignment < SendWithArguments
      def initialize(line, receiver, name, arguments)
        @line = line

        @receiver = receiver
        @privately = receiver.kind_of?(Self) ? true : false

        @name = :"#{name}="

        @arguments = ActualArguments.new line, arguments
      end

      def sexp_name
        :attrasgn
      end
    end

    class ElementAssignment < SendWithArguments
      def initialize(line, receiver, arguments)
        @line = line

        @receiver = receiver
        @privately = receiver.kind_of?(Self) ? true : false

        @name = :[]=

        case arguments
        when PushArgs
          @arguments = PushActualArguments.new arguments
        else
          @arguments = ActualArguments.new line, arguments
        end
      end

      def sexp_name
        :attrasgn
      end
    end

    class PreExe < Node
      attr_accessor :block

      def initialize(line)
        @line = line
      end

      def to_sexp
      end

      def pre_sexp
        @block.to_sexp.insert 1, :pre_exe
      end
    end

    class PreExe19 < PreExe
    end

    class PushActualArguments
      def initialize(pa)
        @arguments = pa.arguments
        @value = pa.value
      end

      def size
        splat? ? 1 : @arguments.size + 1
      end

      def splat?
        @arguments.kind_of? SplatValue or @arguments.kind_of? ConcatArgs
      end

      def to_sexp
        [@arguments.to_sexp, @value.to_sexp]
      end
    end

    class BlockPass < Node
      attr_accessor :body

      def initialize(line, body)
        @line = line
        @body = body
      end

      def convert(g)
        nil_block = g.new_label
        g.dup
        g.is_nil
        g.git nil_block

        g.push_cpath_top
        g.find_const :Proc

        g.swap
        g.send :__from_block__, 1

        nil_block.set!
      end

      def to_sexp
        [:block_pass, @body.to_sexp]
      end
    end

    class BlockPass19 < BlockPass
      attr_accessor :arguments

      def initialize(line, arguments, body)
        super(line, body)
        @arguments = arguments
      end
    end

    class CollectSplat < Node
      def initialize(line, *parts)
        @line = line
        @splat = parts.shift
        @last = parts.pop
        @array = parts
      end

      def to_sexp
        [:collect_splat] + @parts.map { |x| x.to_sexp }
      end
    end

    class ActualArguments < Node
      attr_accessor :array, :splat

      def initialize(line, arguments=nil)
        @line = line
        @splat = nil

        case arguments
        when SplatValue
          @splat = arguments
          @array = []
        when ConcatArgs
          case arguments.array
          when ArrayLiteral
            @array = arguments.array.body
            @splat = SplatValue.new line, arguments.rest
          when PushArgs
            @array = []
            node = SplatValue.new line, arguments.rest
            @splat = CollectSplat.new line, arguments.array, node
          else
            @array = []
            @splat = CollectSplat.new line, arguments.array, arguments.rest
          end
        when PushArgs
          if arguments.arguments.kind_of? ConcatArgs
            if ary = arguments.arguments.peel_lhs
              @array = ary
            else
              @array = []
            end
          else
            @array = []
          end

          @splat = CollectSplat.new line, arguments.arguments, arguments.value
        when ArrayLiteral
          @array = arguments.body
        when nil
          @array = []
        else
          @array = [arguments]
        end
      end

      def size
        @array.size
      end

      def stack_size
        size = @array.size
        size += 1 if splat?
        size
      end

      def splat?
        not @splat.nil?
      end

      def to_sexp
        sexp = @array.map { |x| x.to_sexp }
        sexp << @splat.to_sexp if @splat
        sexp
      end
    end

    class Iter < Node
      include Compiler::LocalVariables

      attr_accessor :parent, :arguments, :body

      def initialize(line, arguments, body)
        @line = line
        @arguments = IterArguments.new line, arguments
        @body = body || NilLiteral.new(line)
      end

      # 1.8 doesn't support declared Iter locals
      def block_local?(name)
        false
      end

      def module?
        false
      end

      def nest_scope(scope)
        scope.parent = self
      end

      # A nested scope is looking up a local variable. If the variable exists
      # in our local variables hash, return a nested reference to it. If it
      # exists in an enclosing scope, increment the depth of the reference
      # when it passes through this nested scope (i.e. the depth of a
      # reference is a function of the nested scopes it passes through from
      # the scope it is defined in to the scope it is used in).
      def search_local(name)
        if variable = variables[name]
          variable.nested_reference
        elsif block_local?(name)
          new_local name
        elsif reference = @parent.search_local(name)
          reference.depth += 1
          reference
        end
      end

      def new_local(name)
        variable = Compiler::LocalVariable.new allocate_slot
        variables[name] = variable
      end

      def new_nested_local(name)
        new_local(name).nested_reference
      end

      # If the local variable exists in this scope, set the local variable
      # node attribute to a reference to the local variable. If the variable
      # exists in an enclosing scope, set the local variable node attribute to
      # a nested reference to the local variable. Otherwise, create a local
      # variable in this scope and set the local variable node attribute.
      def assign_local_reference(var)
        if variable = variables[var.name]
          var.variable = variable.reference
        elsif block_local?(var.name)
          variable = new_local var.name
          var.variable = variable.reference
        elsif reference = @parent.search_local(var.name)
          reference.depth += 1
          var.variable = reference
        else
          variable = new_local var.name
          var.variable = variable.reference
        end
      end

      def sexp_name
        :iter
      end

      def to_sexp
        [sexp_name, @arguments.to_sexp, @body.to_sexp]
      end
    end

    class Iter19 < Iter
      def initialize(line, arguments, body)
        @line = line
        @arguments = arguments || IterArguments.new(line, nil)
        @body = body || NilLiteral.new(line)

        if @body.kind_of?(Block) and @body.locals
          @locals = @body.locals.body.map { |x| x.value }
        else
          @locals = nil
        end
      end

      def block_local?(name)
        @locals.include?(name) if @locals
      end
    end

    class IterArguments < Node
      attr_accessor :prelude, :arity, :optional, :arguments, :splat_index
      attr_accessor :required_args

      def initialize(line, arguments)
        @line = line
        @optional = 0
        @arguments = nil

        @splat_index = -1
        @required_args = 0
        @splat = nil
        @block = nil
        @prelude = nil

        case arguments
        when Fixnum
          @splat_index = nil
          @arity = 0
          @prelude = nil
        when MultipleAssignment
          arguments.iter_arguments

          if arguments.splat
            case arguments.splat
            when EmptySplat
              @splat_index = -2
              arguments.splat = nil
              @prelude = :empty
            else
              @splat = arguments.splat = arguments.splat.value
            end

            @optional = 1
            if arguments.left
              @prelude = :multi
              size = arguments.left.body.size
              @arity = -(size + 1)
              @required_args = size
            else
              @prelude = :splat unless @prelude
              @arity = -1
            end
          elsif arguments.left
            size = arguments.left.body.size
            @prelude = :multi
            @arity = size
            @required_args = size

            # distinguish { |a, | ... } from { |a| ... }
            @splat_index = nil unless size == 1
          else
            @splat_index = 0
            @prelude = :multi
            @arity = -1
          end

          @block = arguments.block

          @arguments = arguments
        when nil
          @arity = -1
          @splat_index = -2 # -2 means accept the splat, but don't store it anywhere
          @prelude = nil
        when BlockPass
          @arity = -1
          @splat_index = -2
          @prelude = nil
          @block = arguments
        else # Assignment
          @splat_index = nil
          @arguments = arguments
          @arity = 1
          @required_args = 1
          @prelude = :single
        end
      end

      alias_method :total_args, :required_args

      def post_args
        0
      end

      def names
        case @arguments
        when MultipleAssignment
          if arguments = @arguments.left.body
            array = arguments.map { |x| x.name }
          else
            array = []
          end

          if @arguments.splat.kind_of? SplatAssignment
            array << @arguments.splat.name
          end

          array
        when nil
          []
        else
          [@arguments.name]
        end
      end

      def to_sexp
        if @arguments
          @arguments.to_sexp
        elsif @arity == 0
          0
        else
          nil
        end
      end
    end

    class For < Iter
      def nest_scope(scope)
        scope.parent = self
      end

      def search_local(name)
        if reference = @parent.search_local(name)
          reference.depth += 1
          reference
        end
      end

      def new_nested_local(name)
        reference = @parent.new_nested_local name
        reference.depth += 1
        reference
      end

      def assign_local_reference(var)
        unless reference = search_local(var.name)
          reference = new_nested_local var.name
        end

        var.variable = reference
      end

      def sexp_name
        :for
      end
    end

    class For19Arguments < Node
      def initialize(line, arguments)
        @line = line
        @arguments = arguments

        if @arguments.kind_of? MultipleAssignment
          @args = 0
          @splat = 0
        else
          @args = 1
          @splat = nil
        end
      end

      def required_args
        @args
      end

      def total_args
        @args
      end

      def post_args
        0
      end

      def splat_index
        @splat
      end
    end

    class For19 < For
      def initialize(line, arguments, body)
        @line = line
        @arguments = For19Arguments.new line, arguments
        @body = body || NilLiteral.new(line)

        new_local :"$for_args"
      end
    end

    class Negate < Node
      attr_accessor :value

      def initialize(line, value)
        @line = line
        @value = value
      end

      def to_sexp
        [:negate, @value.to_sexp]
      end
    end

    class Super < SendWithArguments
      attr_accessor :name, :block

      def initialize(line, arguments)
        @line = line
        @block = nil
        @name = nil
        @arguments = ActualArguments.new line, arguments
      end

      def to_sexp
        arguments_sexp :super
      end
    end

    class Yield < SendWithArguments
      attr_accessor :flags

      def initialize(line, arguments, unwrap)
        @line = line

        if arguments.kind_of? ArrayLiteral and not unwrap
          arguments = ArrayLiteral.new line, [arguments]
        end

        @arguments = ActualArguments.new line, arguments
        @argument_count = @arguments.size
        @yield_splat = false

        if @arguments.splat?
          splat = @arguments.splat.value
          if (splat.kind_of? ArrayLiteral or splat.kind_of? EmptyArray) and not unwrap
            @argument_count += 1
          else
            @yield_splat = true
          end
        end
      end

      def to_sexp
        arguments_sexp :yield
      end
    end

    class ZSuper < Super
      def initialize(line)
        @line = line
        @block = nil
      end

      def to_sexp
        [:zsuper]
      end
    end
  end
end
