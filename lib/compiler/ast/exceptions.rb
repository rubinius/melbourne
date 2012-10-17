# -*- encoding: us-ascii -*-

module Rubinius
  module AST
    class Begin < Node
      attr_accessor :rescue

      def initialize(line, body)
        @line = line
        @rescue = body || NilLiteral.new(line)
      end

      def to_sexp
        @rescue.to_sexp
      end
    end

    EnsureType = 1

    class Ensure < Node
      attr_accessor :body, :ensure

      def initialize(line, body, ensr)
        @line = line
        @body = body || NilLiteral.new(line)
        @ensure = ensr
      end

      def to_sexp
        [:ensure, @body.to_sexp, @ensure.to_sexp]
      end
    end

    RescueType = 0

    class Rescue < Node
      attr_accessor :body, :rescue, :else

      def initialize(line, body, rescue_body, else_body)
        @line = line
        @body = body
        @rescue = rescue_body
        @else = else_body
      end

      def to_sexp
        sexp = [:rescue, @body.to_sexp, @rescue.to_sexp]
        sexp << @else.to_sexp if @else
        sexp
      end
    end

    class RescueCondition < Node
      attr_accessor :conditions, :assignment, :body, :next, :splat

      def initialize(line, conditions, body, nxt)
        @line = line
        @next = nxt
        @splat = nil
        @assignment = nil

        case conditions
        when ArrayLiteral
          @conditions = conditions
        when ConcatArgs
          @conditions = conditions.array
          @splat = RescueSplat.new line, conditions.rest
        when SplatValue
          @splat = RescueSplat.new line, conditions.value
        when nil
          condition = ConstantAccess.new line, :StandardError
          @conditions = ArrayLiteral.new line, [condition]
        end

        case body
        when Block
          @assignment = body.array.shift if assignment? body.array.first
          @body = body
        when nil
          @body = NilLiteral.new line
        else
          if assignment? body
            @assignment = body
            @body = NilLiteral.new line
          else
            @body = body
          end
        end
      end

      def assignment?(node)
        case node
        when VariableAssignment
          value = node.value
        when AttributeAssignment
          value = node.arguments.array.last
        else
          return false
        end

        return true if value.kind_of? CurrentException
      end

      def to_sexp
        array = @conditions.to_sexp
        array << @assignment.to_sexp if @assignment
        array << @splat.to_sexp if @splat

        sexp = [:resbody, array]
        case @body
        when Block
          sexp << (@body ? @body.array.map { |x| x.to_sexp } : nil)
        when nil
          sexp << nil
        else
          sexp << @body.to_sexp
        end

        sexp << @next.to_sexp if @next

        sexp
      end
    end

    class RescueSplat < Node
      attr_accessor :value

      def initialize(line, value)
        @line = line
        @value = value
      end

      def to_sexp
        [:splat, @value.to_sexp]
      end
    end
  end
end
