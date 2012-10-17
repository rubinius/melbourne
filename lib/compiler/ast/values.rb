# -*- encoding: us-ascii -*-

module Rubinius
  module AST
    class SplatValue < Node
      attr_accessor :value

      def initialize(line, value)
        @line = line
        @value = value
      end

      def to_sexp
        [:splat, @value.to_sexp]
      end
    end

    class ConcatArgs < Node
      attr_accessor :array, :rest

      def initialize(line, array, rest)
        @line = line
        @array = array
        @rest = rest
      end

      def to_sexp
        [:argscat, @array.to_sexp, @rest.to_sexp]
      end
    end

    class PushArgs < Node
      attr_accessor :arguments, :value

      def initialize(line, arguments, value)
        @line = line
        @arguments = arguments
        @value = value
      end

      def to_sexp
        [:argspush, @arguments.to_sexp, @value.to_sexp]
      end
    end


    class SValue < Node
      attr_accessor :value

      def initialize(line, value)
        @line = line
        @value = value
      end

      def to_sexp
        [:svalue, @value.to_sexp]
      end
    end

    class ToArray < Node
      attr_accessor :value

      def initialize(line, value)
        @line = line
        @value = value
      end

      def to_sexp
        [:to_ary, @value.to_sexp]
      end
    end

    class ToString < Node
      attr_accessor :value

      def initialize(line, value)
        @line = line
        @value = value
      end

      def to_sexp
        sexp = [:evstr]
        sexp << @value.to_sexp if @value
        sexp
      end
    end
  end
end
