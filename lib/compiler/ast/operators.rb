# -*- encoding: us-ascii -*-

module Rubinius
  module AST
    class And < Node
      attr_accessor :left, :right

      def initialize(line, left, right)
        @line = line
        @left = left
        @right = right
      end

      def sexp_name
        :and
      end

      def to_sexp
        [sexp_name, @left.to_sexp, @right.to_sexp]
      end
    end

    class Or < And
      def sexp_name
        :or
      end
    end

    class Not < Node
      attr_accessor :value

      def initialize(line, value)
        @line = line
        @value = value
      end

      def to_sexp
        [:not, @value.to_sexp]
      end
    end

    class OpAssign1 < Node
      attr_accessor :receiver, :op, :arguments, :value

      def initialize(line, receiver, arguments, op, value)
        @line = line
        @receiver = receiver
        @op = op
        arguments = nil if arguments.is_a?(EmptyArray)
        @arguments = ActualArguments.new line, arguments
        @value = value
      end

      def to_sexp
        arguments = [:arglist] + @arguments.to_sexp
        op = @op == :or ? :"||" : :"&&"
        [:op_asgn1, @receiver.to_sexp, arguments, op, @value.to_sexp]
      end
    end

    class OpAssign2 < Node
      attr_accessor :receiver, :name, :assign, :op, :value

      def initialize(line, receiver, name, op, value)
        @line = line
        @receiver = receiver
        @name = name
        @op = op
        @value = value
        @assign = name.to_s[-1] == ?= ? name : :"#{name}="
      end

      def to_sexp
        op = @op == :or ? :"||" : :"&&"
        [:op_asgn2, @receiver.to_sexp, :"#{@name}=", op, @value.to_sexp]
      end
    end

    class OpAssignAnd < Node
      attr_accessor :left, :right

      def initialize(line, left, right)
        @line = line
        @left = left
        @right = right
      end

      def sexp_name
        :op_asgn_and
      end

      def to_sexp
        [sexp_name, @left.to_sexp, @right.to_sexp]
      end
    end

    class OpAssignOr < OpAssignAnd
      def sexp_name
        :op_asgn_or
      end
    end

    class OpAssignOr19 < OpAssignOr
    end
  end
end
