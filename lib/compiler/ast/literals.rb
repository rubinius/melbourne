# -*- encoding: us-ascii -*-

module Rubinius
  module AST
    class ArrayLiteral < Node
      attr_accessor :body

      def initialize(line, array)
        @line = line
        @body = array
      end

      def to_sexp
        @body.inject([:array]) { |s, x| s << x.to_sexp }
      end
    end

    class EmptyArray < Node
      def to_sexp
        [:array]
      end
    end

    class FalseLiteral < Node
      def to_sexp
        [:false]
      end
    end

    class TrueLiteral < Node
      def to_sexp
        [:true]
      end
    end

    class FloatLiteral < Node
      attr_accessor :value

      def initialize(line, str)
        @line = line
        @value = str.to_f
      end

      def to_sexp
        [:lit, @value]
      end
    end

    class HashLiteral < Node
      attr_accessor :array

      def initialize(line, array)
        @line = line
        @array = array
      end

      def to_sexp
        @array.inject([:hash]) { |s, x| s << x.to_sexp }
      end
    end

    class SymbolLiteral < Node
      attr_accessor :value

      def initialize(line, sym)
        @line = line
        @value = sym
      end

      def to_sexp
        [:lit, @value]
      end
    end

    class NilLiteral < Node
      def to_sexp
        [:nil]
      end
    end

    class NumberLiteral < Node
      attr_accessor :value

      def initialize(line, value)
        @line = line
        @value = value
      end

      def to_sexp
        [:lit, @value]
      end
    end

    class FixnumLiteral < NumberLiteral
      def initialize(line, value)
        @line = line
        @value = value
      end
    end

    class Range < Node
      attr_accessor :start, :finish

      def initialize(line, start, finish)
        @line = line
        @start = start
        @finish = finish
      end

      def to_sexp
        [:dot2, @start.to_sexp, @finish.to_sexp]
      end
    end

    class RangeExclude < Range
      def initialize(line, start, finish)
        @line = line
        @start = start
        @finish = finish
      end

      def to_sexp
        [:dot3, @start.to_sexp, @finish.to_sexp]
      end
    end

    class RegexLiteral < Node
      attr_accessor :source, :options

      def initialize(line, str, flags)
        @line = line
        @source = str
        @options = flags
      end

      def to_sexp
        [:regex, @source, @options]
      end
    end

    class StringLiteral < Node
      attr_accessor :string

      def initialize(line, str)
        @line = line
        @string = str
      end

      def to_sexp
        [:str, @string]
      end
    end

    class DynamicString < StringLiteral
      attr_accessor :array, :options

      def initialize(line, str, array)
        @line = line
        @string = str
        @array = array
      end

      def sexp_name
        :dstr
      end

      def to_sexp
        @array.inject([sexp_name, @string]) { |s, x| s << x.to_sexp }
      end
    end

    class DynamicSymbol < DynamicString
      def sexp_name
        :dsym
      end
    end

    class DynamicExecuteString < DynamicString
      def sexp_name
        :dxstr
      end
    end

    class DynamicRegex < DynamicString
      def initialize(line, str, array, flags)
        super line, str, array
        @options = flags || 0
      end

      def sexp_name
        :dregx
      end
    end

    class DynamicOnceRegex < DynamicRegex
      def sexp_name
        :dregx_once
      end
    end

    class ExecuteString < StringLiteral
      def to_sexp
        [:xstr, @string]
      end
    end
  end
end
