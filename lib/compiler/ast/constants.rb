# -*- encoding: us-ascii -*-

module Rubinius
  module AST

    class TypeConstant < Node
      def initialize(line)
        @line = line
      end
    end

    class ScopedConstant < Node
      attr_accessor :parent, :name

      def initialize(line, parent, name)
        @line = line
        @parent = parent
        @name = name
      end

      def to_sexp
        [:colon2, @parent.to_sexp, @name]
      end

      alias_method :assign_sexp, :to_sexp
    end

    class ToplevelConstant < Node
      attr_accessor :name

      def initialize(line, name)
        @line = line
        @name = name
      end

      def to_sexp
        [:colon3, @name]
      end

      alias_method :assign_sexp, :to_sexp
    end

    class ConstantAccess < Node
      attr_accessor :name

      def initialize(line, name)
        @line = line
        @name = name
      end

      def assign_sexp
        @name
      end

      def to_sexp
        [:const, @name]
      end
    end

    class ConstantAssignment < Node
      attr_accessor :constant, :value

      def initialize(line, expr, value)
        @line = line
        @value = value

        if expr.kind_of? Symbol
          @constant = ConstantAccess.new line, expr
        else
          @constant = expr
        end
      end

      def to_sexp
        sexp = [:cdecl, @constant.assign_sexp]
        sexp << @value.to_sexp if @value
        sexp
      end
    end
  end
end
