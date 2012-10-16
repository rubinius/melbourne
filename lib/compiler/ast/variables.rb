# -*- encoding: us-ascii -*-

module Rubinius
  module AST
    class BackRef < Node
      attr_accessor :kind

      def initialize(line, ref)
        @line = line
        @kind = ref
      end

      Kinds = {
        :~ => 0,
        :& => 1,
        :"`" => 2,
        :"'" => 3,
        :+ => 4
      }

      def mode
        unless mode = Kinds[@kind]
          raise "Unknown backref: #{@kind}"
        end

        mode
      end

      def to_sexp
        [:back_ref, @kind]
      end
    end

    class NthRef < Node
      attr_accessor :which

      def initialize(line, ref)
        @line = line
        @which = ref
      end

      Mode = 5

      def to_sexp
        [:nth_ref, @which]
      end
    end

    class VariableAccess < Node
      attr_accessor :name

      def initialize(line, name)
        @line = line
        @name = name
      end
    end

    class VariableAssignment < Node
      attr_accessor :name, :value

      def initialize(line, name, value)
        @line = line
        @name = name
        @value = value
      end

      def defined(g)
        g.push_literal "assignment"
      end

      def to_sexp
        sexp = [sexp_name, @name]
        sexp << @value.to_sexp if @value
        sexp
      end
    end

    class ClassVariableAccess < VariableAccess
      def to_sexp
        [:cvar, @name]
      end
    end

    class ClassVariableAssignment < VariableAssignment
      def sexp_name
        :cvasgn
      end
    end

    class ClassVariableDeclaration < ClassVariableAssignment
      def sexp_name
        :cvdecl
      end
    end

    class CurrentException < Node
      def to_sexp
        [:gvar, :$!]
      end
    end

    class GlobalVariableAccess < VariableAccess
      EnglishBackrefs = {
        :$LAST_MATCH_INFO => :~,
        :$MATCH => :&,
        :$PREMATCH => :'`',
        :$POSTMATCH => :"'",
        :$LAST_PAREN_MATCH => :+,
      }

      def self.for_name(line, name)
        case name
        when :$!
          CurrentException.new(line)
        when :$~
          BackRef.new(line, :~)
        else
          if backref = EnglishBackrefs[name]
            BackRef.new(line, backref)
          else
            new(line, name)
          end
        end
      end

      def to_sexp
        [:gvar, @name]
      end
    end

    class GlobalVariableAssignment < VariableAssignment
      def sexp_name
        :gasgn
      end
    end

    class SplatAssignment < Node
      attr_accessor :value

      def initialize(line, value)
        @line = line
        @value = value
      end

      def to_sexp
        [:splat_assign, @value.to_sexp]
      end
    end

    class SplatArray < SplatAssignment
      def initialize(line, value, size)
        @line = line
        @value = value
        @size = size
      end

      def to_sexp
        [:splat, @value.to_sexp]
      end
    end

    class SplatWrapped < SplatAssignment
      def to_sexp
        [:splat, @value.to_sexp]
      end
    end

    class EmptySplat < Node
      def initialize(line, size)
        @line = line
        @size = size
      end

      def to_sexp
        [:splat]
      end
    end

    class InstanceVariableAccess < VariableAccess
      def to_sexp
        [:ivar, @name]
      end
    end

    class InstanceVariableAssignment < VariableAssignment
      def sexp_name
        :iasgn
      end
    end

    class LocalVariableAccess < VariableAccess
      include LocalVariable

      def initialize(line, name)
        @line = line
        @name = name
        @variable = nil
      end

      def to_sexp
        [:lvar, @name]
      end
    end

    class LocalVariableAssignment < VariableAssignment
      include LocalVariable

      def initialize(line, name, value)
        @line = line
        @name = name
        @value = value
        @variable = nil
      end

      def sexp_name
        :lasgn
      end
    end

    class PostArg < Node
      attr_accessor :into, :rest

      def initialize(line, into, rest)
        @line = line
        @into = into
        @rest = rest
      end
    end

    class MultipleAssignment < Node
      attr_accessor :left, :right, :splat, :block

      def initialize(line, left, right, splat)
        @line = line
        @left = left
        @right = right
        @splat = nil
        @block = nil # support for |&b|
        @post = nil # in `a,*b,c`, c is in post.

        if Rubinius.ruby18?
          @fixed = right.kind_of?(ArrayLiteral) ? true : false
        elsif splat.kind_of?(PostArg)
          @fixed = false
          @post = splat.rest
          splat = splat.into
        elsif right.kind_of?(ArrayLiteral)
          @fixed = right.body.size > 1
        else
          @fixed = false
        end

        if splat.kind_of? Node
          if @left
            if right
              @splat = SplatAssignment.new line, splat
            else
              @splat = SplatWrapped.new line, splat
            end
          elsif @fixed
            @splat = SplatArray.new line, splat, right.body.size
          elsif right.kind_of? SplatValue
            @splat = splat
          else
            @splat = SplatWrapped.new line, splat
          end
        elsif splat
          # We need a node for eg { |*| } and { |a, *| }
          size = @fixed ? right.body.size : 0
          @splat = EmptySplat.new line, size
        end
      end

      def pad_short(g)
        short = @left.body.size - @right.body.size
        if short > 0
          short.times { g.push :nil }
          g.make_array 0 if @splat
        end
      end

      def pop_excess(g)
        excess = @right.body.size - @left.body.size
        excess.times { g.pop } if excess > 0
      end

      def make_array(g)
        size = @right.body.size - @left.body.size
        g.make_array size if size >= 0
      end

      def rotate(g)
        if @splat
          size = @left.body.size + 1
        else
          size = @right.body.size
        end
        g.rotate size
      end

      def iter_arguments
        @iter_arguments = true
      end

      def declare_local_scope(scope)
        # Fix the scope for locals introduced by the left. We
        # do this before running the code for the right so that
        # right side sees the proper scoping of the locals on the left.

        if @left
          @left.body.each do |var|
            case var
            when LocalVariable
              scope.assign_local_reference var
            when MultipleAssignment
              var.declare_local_scope(scope)
            end
          end
        end

        if @splat and @splat.kind_of?(SplatAssignment)
          if @splat.value.kind_of?(LocalVariable)
            scope.assign_local_reference @splat.value
          end
        end
      end

      def to_sexp
        left = @left ? @left.to_sexp : [:array]
        left << [:splat, @splat.to_sexp] if @splat
        left << @block.to_sexp if @block

        sexp = [:masgn, left]
        sexp << @right.to_sexp if @right
        sexp
      end
    end

    class PatternVariable < Node
      include LocalVariable

      attr_accessor :name, :value

      def initialize(line, name)
        @line = line
        @name = name
        @variable = nil
      end
    end
  end
end
