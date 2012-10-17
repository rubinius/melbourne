# -*- encoding: us-ascii -*-

module Rubinius
  module AST
    class Alias < Node
      attr_accessor :to, :from

      def initialize(line, to, from)
        @line = line
        @to = to
        @from = from
      end

      def to_sexp
        [:alias, @to.to_sexp, @from.to_sexp]
      end
    end

    class VAlias < Alias
      def to_sexp
        [:valias, @to, @from]
      end
    end

    class Undef < Node
      attr_accessor :name

      def initialize(line, sym)
        @line = line
        @name = sym
      end

      def to_sexp
        [:undef, @name.to_sexp]
      end
    end

    # Is it weird that Block has the :arguments attribute? Yes. Is it weird
    # that MRI parse tree puts arguments and block_arg in Block? Yes. So we
    # make do and pull them out here rather than having something else reach
    # inside of Block.
    class Block < Node
      attr_accessor :array, :locals

      def initialize(line, array)
        @line = line
        @array = array

        # These are any local variable that are declared as explicit
        # locals for this scope. This is only used by the |a;b| syntax.
        @locals = nil
      end

      def strip_arguments
        if @array.first.kind_of? FormalArguments
          node = @array.shift
          if @array.first.kind_of? BlockArgument
            node.block_arg = @array.shift
          end
          return node
        end
      end

      def to_sexp
        @array.inject([:block]) { |s, x| s << x.to_sexp }
      end
    end

    class ClosedScope < Node
      include Compiler::LocalVariables

      attr_accessor :body

      # A nested scope is looking up a local variable. If the variable exists
      # in our local variables hash, return a nested reference to it.
      def search_local(name)
        if variable = variables[name]
          variable.nested_reference
        end
      end

      def new_local(name)
        variable = Compiler::LocalVariable.new allocate_slot
        variables[name] = variable
      end

      def new_nested_local(name)
        new_local(name).nested_reference
      end

      # There is no place above us that may contain a local variable. Set the
      # local in our local variables hash if not set. Set the local variable
      # node attribute to a reference to the local variable.
      def assign_local_reference(var)
        unless variable = variables[var.name]
          variable = new_local var.name
        end

        var.variable = variable.reference
      end

      def nest_scope(scope)
        scope.parent = self
      end

      def module?
        false
      end

      def to_sexp
        sexp = [:scope]
        sexp << @body.to_sexp if @body
        sexp
      end
    end

    class Define < ClosedScope
      attr_accessor :name, :arguments

      def initialize(line, name, block)
        @line = line
        @name = name
        @arguments = block.strip_arguments
        block.array << NilLiteral.new(line) if block.array.empty?
        @body = block
      end

      def to_sexp
        [:defn, @name, @arguments.to_sexp, [:scope, @body.to_sexp]]
      end
    end

    class DefineSingleton < Node
      attr_accessor :receiver, :body

      def initialize(line, receiver, name, block)
        @line = line
        @receiver = receiver
        @body = DefineSingletonScope.new line, name, block
      end

      def to_sexp
        [:defs, @receiver.to_sexp, @body.name,
          @body.arguments.to_sexp, [:scope, @body.body.to_sexp]]
      end
    end

    class DefineSingletonScope < Define
      def initialize(line, name, block)
        super line, name, block
      end

    end

    class FormalArguments < Node
      attr_accessor :names, :required, :optional, :defaults, :splat
      attr_reader :block_arg

      def initialize(line, args, defaults, splat)
        @line = line
        @defaults = nil
        @block_arg = nil

        if defaults
          defaults = DefaultArguments.new line, defaults
          @defaults = defaults
          @optional = defaults.names

          stop = defaults.names.first
          last = args.each_with_index { |a, i| break i if a == stop }
          @required = args[0, last]
        else
          @required = args.dup
          @optional = []
        end

        if splat.kind_of? Symbol
          args << splat
        elsif splat
          splat = :@unnamed_splat
          args << splat
        end
        @names = args
        @splat = splat
      end

      def block_arg=(node)
        @names << node.name
        @block_arg = node
      end

      def required_args
        @required.size
      end

      alias_method :arity, :required_args

      def post_args
        0
      end

      def total_args
        @required.size + @optional.size
      end

      def splat_index
        if @splat
          index = @names.size
          index -= 1 if @block_arg
          index -= 1 if @splat.kind_of? Symbol
          index
        end
      end

      def map_arguments(scope)
        @required.each { |arg| scope.new_local arg }
        @defaults.map_arguments scope if @defaults
        scope.new_local @splat if @splat.kind_of? Symbol
        scope.assign_local_reference @block_arg if @block_arg
      end

      def to_actual(line)
        arguments = ActualArguments.new line

        last = -1
        last -= 1 if @block_arg and @block_arg.name == names[last]
        last -= 1 if @splat == names[last]

        arguments.array = @names[0..last].map { |name| LocalVariableAccess.new line, name }

        if @splat.kind_of? Symbol
          arguments.splat = SplatValue.new(line, LocalVariableAccess.new(line, @splat))
        end

        arguments
      end

      def to_sexp
        sexp = [:args]

        @required.each { |x| sexp << x }
        sexp += @defaults.names if @defaults

        if @splat == :@unnamed_splat
          sexp << :*
        elsif @splat
          sexp << :"*#{@splat}"
        end

        sexp += @post if @post

        sexp << :"&#{@block_arg.name}" if @block_arg

        sexp << [:block] + @defaults.to_sexp if @defaults

        sexp
      end
    end

    class FormalArguments19 < FormalArguments
      attr_accessor :post

      def initialize(line, required, optional, splat, post, block)
        @line = line
        @defaults = nil
        @block_arg = nil
        @splat_index = nil

        @required = []
        names = []

        if required
          required.each do |arg|
            case arg
            when Symbol
              names << arg
              @required << arg
            when MultipleAssignment
              @required << PatternArguments.from_masgn(arg)
              @splat_index = -4 if @required.size == 1
            end
          end
        end

        if optional
          @defaults = DefaultArguments.new line, optional
          @optional = @defaults.names
          names.concat @optional
        else
          @optional = []
        end

        case splat
        when Symbol
          names << splat
        when true
          splat = :@unnamed_splat
          names << splat
        when false
          @splat_index = -3
          splat = nil
        end

        if post
          names.concat post
          @post = post
        else
          @post = []
        end

        if block
          @block_arg = BlockArgument.new line, block
          names << block
        end

        @splat = splat
        @names = names
      end

      def required_args
        @required.size + @post.size
      end

      def post_args
        @post.size
      end

      def total_args
        @required.size + @optional.size + @post.size
      end

      def splat_index
        return @splat_index if @splat_index

        if @splat
          index = @names.size
          index -= 1 if @block_arg
          index -= 1 if @splat.kind_of? Symbol
          index -= @post.size
          index
        end
      end

      def map_arguments(scope)
        @required.each_with_index do |arg, index|
          case arg
          when PatternArguments
            arg.map_arguments scope
          when Symbol
            @required[index] = arg = :"_#{index}" if arg == :_
            scope.new_local arg
          end
        end

        @defaults.map_arguments scope if @defaults
        scope.new_local @splat if @splat.kind_of? Symbol
        @post.each { |arg| scope.new_local arg }
        scope.assign_local_reference @block_arg if @block_arg
      end

    end

    class PatternArguments < Node
      attr_accessor :arguments, :argument

      def self.from_masgn(node)
        array = []
        node.left.body.map do |n|
          case n
          when MultipleAssignment
            array << PatternArguments.from_masgn(n)
          when LocalVariable
            array << PatternVariable.new(n.line, n.name)
          end
        end

        PatternArguments.new node.line, ArrayLiteral.new(node.line, array)
      end

      def initialize(line, arguments)
        @line = line
        @arguments = arguments
        @argument = nil
      end

      # Assign the left-most, depth-first PatternVariable so that this local
      # will be assigned the passed argument at that position. The rest of the
      # pattern will be destructured from the value of this assignment.
      def map_arguments(scope)
        arguments = @arguments.body
        while arguments
          node = arguments.first
          if node.kind_of? PatternVariable
            @argument = node
            scope.assign_local_reference node
            return
          end
          arguments = node.arguments.body
        end
      end

    end

    class DefaultArguments < Node
      attr_accessor :arguments, :names

      def initialize(line, block)
        @line = line
        array = block.array
        @names = array.map { |a| a.name }
        @arguments = array
      end

      def map_arguments(scope)
        @arguments.each { |var| scope.assign_local_reference var }
      end

      def to_sexp
        @arguments.map { |x| x.to_sexp }
      end
    end

    module LocalVariable
      attr_accessor :variable
    end

    class BlockArgument < Node
      include LocalVariable

      attr_accessor :name

      def initialize(line, name)
        @line = line
        @name = name
      end
    end

    class Class < Node
      attr_accessor :name, :superclass, :body

      def initialize(line, name, superclass, body)
        @line = line

        @superclass = superclass ? superclass : NilLiteral.new(line)

        case name
        when Symbol
          @name = ClassName.new line, name, @superclass
        when ToplevelConstant
          @name = ToplevelClassName.new line, name, @superclass
        else
          @name = ScopedClassName.new line, name, @superclass
        end

        if body
          @body = ClassScope.new line, @name, body
        else
          @body = EmptyBody.new line
        end
      end

      def to_sexp
        superclass = @superclass.kind_of?(NilLiteral) ? nil : @superclass.to_sexp
        [:class, @name.to_sexp, superclass, @body.to_sexp]
      end
    end

    class ClassScope < ClosedScope
      def initialize(line, name, body)
        @line = line
        @name = name.name
        @body = body
      end

      def module?
        true
      end
    end

    class ClassName < Node
      attr_accessor :name, :superclass

      def initialize(line, name, superclass)
        @line = line
        @name = name
        @superclass = superclass
      end

      def to_sexp
        @name
      end
    end

    class ToplevelClassName < ClassName
      def initialize(line, node, superclass)
        @line = line
        @name = node.name
        @superclass = superclass
      end

      def to_sexp
        [:colon3, @name]
      end
    end

    class ScopedClassName < ClassName
      attr_accessor :parent

      def initialize(line, node, superclass)
        @line = line
        @name = node.name
        @parent = node.parent
        @superclass = superclass
      end

      def to_sexp
        [:colon2, @parent.to_sexp, @name]
      end
    end

    class Module < Node
      attr_accessor :name, :body

      def initialize(line, name, body)
        @line = line

        case name
        when Symbol
          @name = ModuleName.new line, name
        when ToplevelConstant
          @name = ToplevelModuleName.new line, name
        else
          @name = ScopedModuleName.new line, name
        end

        if body
          @body = ModuleScope.new line, @name, body
        else
          @body = EmptyBody.new line
        end
      end

      def to_sexp
        [:module, @name.to_sexp, @body.to_sexp]
      end
    end

    class EmptyBody < Node
      def to_sexp
        [:scope]
      end
    end

    class ModuleName < Node
      attr_accessor :name

      def initialize(line, name)
        @line = line
        @name = name
      end

      def to_sexp
        @name
      end
    end

    class ToplevelModuleName < ModuleName
      def initialize(line, node)
        @line = line
        @name = node.name
      end

      def to_sexp
        [:colon3, @name]
      end
    end

    class ScopedModuleName < ModuleName
      attr_accessor :parent

      def initialize(line, node)
        @line = line
        @name = node.name
        @parent = node.parent
      end

      def to_sexp
        [:colon2, @parent.to_sexp, @name]
      end
    end

    class ModuleScope < ClosedScope
      def initialize(line, name, body)
        @line = line
        @name = name.name
        @body = body
      end

      def module?
        true
      end
    end

    class SClass < Node
      attr_accessor :receiver

      def initialize(line, receiver, body)
        @line = line
        @receiver = receiver
        @body = SClassScope.new line, body
      end

      def to_sexp
        [:sclass, @receiver.to_sexp, @body.to_sexp]
      end
    end

    class SClassScope < ClosedScope
      def initialize(line, body)
        @line = line
        @body = body
        @name = nil
      end
    end

    class Container < ClosedScope
      attr_accessor :file, :name, :variable_scope, :pre_exe

      def initialize(body)
        @body = body || NilLiteral.new(1)
        @pre_exe = []
      end

      def push_state(g)
        g.push_state self
      end

      def pop_state(g)
        g.pop_state
      end

      def to_sexp
        sexp = [sexp_name]
        @pre_exe.each { |pe| sexp << pe.pre_sexp }
        sexp << @body.to_sexp
        sexp
      end
    end

    class EvalExpression < Container
      def initialize(body)
        super body
        @name = :__eval_script__
      end

      def should_cache?
        !@body.kind_of?(AST::ClosedScope)
      end

      def search_scopes(name)
        depth = 1
        scope = @variable_scope
        while scope
          if !scope.method.for_eval? and slot = scope.method.local_slot(name)
            return Compiler::NestedLocalVariable.new(depth, slot)
          elsif scope.eval_local_defined?(name, false)
            return Compiler::EvalLocalVariable.new(name)
          end

          depth += 1
          scope = scope.parent
        end
      end

      # Returns a cached reference to a variable or searches all
      # surrounding scopes for a variable. If no variable is found,
      # it returns nil and a nested scope will create the variable
      # in itself.
      def search_local(name)
        if variable = variables[name]
          return variable.nested_reference
        end

        if variable = search_scopes(name)
          variables[name] = variable
          return variable.nested_reference
        end
      end

      def new_local(name)
        variable = Compiler::EvalLocalVariable.new name
        variables[name] = variable
      end

      def assign_local_reference(var)
        unless reference = search_local(var.name)
          variable = new_local var.name
          reference = variable.reference
        end

        var.variable = reference
      end

      def push_state(g)
        g.push_state self
        g.state.push_eval self
      end

      def sexp_name
        :eval
      end
    end

    class Snippet < Container
      def initialize(body)
        super body
        @name = :__snippet__
      end

      def sexp_name
        :snippet
      end
    end

    class Script < Container
      def initialize(body)
        super body
        @name = :__script__
      end

      def sexp_name
        :script
      end
    end

    class Defined < Node
      attr_accessor :expression

      def initialize(line, expr)
        @line = line
        @expression = expr
      end

      def to_sexp
        [:defined, @expression.to_sexp]
      end
    end
  end
end
