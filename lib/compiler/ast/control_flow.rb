# -*- encoding: us-ascii -*-

module Rubinius
  module AST
    class Case < Node
      attr_accessor :whens, :else

      def initialize(line, whens, else_body)
        @line = line
        @whens = whens
        @else = else_body || NilLiteral.new(line)
      end

      def receiver_sexp
        nil
      end

      def to_sexp
        else_sexp = @else.kind_of?(NilLiteral) ? nil : @else.to_sexp
        sexp = [:case, receiver_sexp]
        sexp << [:whens] + @whens.map { |x| x.to_sexp }
        sexp << else_sexp
        sexp
      end
    end

    class ReceiverCase < Case
      attr_accessor :receiver

      def initialize(line, receiver, whens, else_body)
        @line = line
        @receiver = receiver
        @whens = whens
        @else = else_body || NilLiteral.new(line)
      end

      def receiver_sexp
        @receiver.to_sexp
      end
    end

    class When < Node
      attr_accessor :conditions, :body, :single, :splat

      def initialize(line, conditions, body)
        @line = line
        @body = body || NilLiteral.new(line)
        @splat = nil
        @single = nil

        if conditions.kind_of? ConcatArgs
          @splat = SplatWhen.new line, conditions.rest
          conditions = conditions.array
        end

        if conditions.kind_of? ArrayLiteral
          if conditions.body.last.kind_of? When
            last = conditions.body.pop
            if last.conditions.kind_of? ArrayLiteral
              conditions.body.concat last.conditions.body
            elsif last.single
              @splat = SplatWhen.new line, last.single
            else
              @splat = SplatWhen.new line, last.conditions
            end
          end

          if conditions.body.size == 1 and !@splat
            @single = conditions.body.first
          else
            @conditions = conditions
          end
        elsif conditions.kind_of? SplatValue
          @splat = SplatWhen.new line, conditions.value
          @conditions = nil
        else
          @conditions = conditions
        end
      end

      def to_sexp
        if @single
          conditions_sexp = [:array, @single.to_sexp]
        else
          conditions_sexp = @conditions.to_sexp
          conditions_sexp << @splat.to_sexp if @splat
        end
        [:when, conditions_sexp, @body.to_sexp]
      end
    end

    class SplatWhen < Node
      attr_accessor :condition

      def initialize(line, condition)
        @line = line
        @condition = condition
      end

      def to_sexp
        [:when, @condition.to_sexp, nil]
      end
    end

    class Flip2 < Node
      def initialize(line, start, finish)
        @line = line
        @start = start
        @finish = finish
      end

      def sexp_name
        :flip2
      end

      def exclusive?
        false
      end

      def to_sexp
        [sexp_name, @start.to_sexp, @finish.to_sexp]
      end
    end

    class Flip3 < Flip2
      def sexp_name
        :flip3
      end

      def exclusive?
        true
      end
    end

    class If < Node
      attr_accessor :condition, :body, :else

      def initialize(line, condition, body, else_body)
        @line = line
        @condition = condition
        @body = body || NilLiteral.new(line)
        @else = else_body || NilLiteral.new(line)
      end

      def to_sexp
        else_sexp = @else.kind_of?(NilLiteral) ? nil : @else.to_sexp
        [:if, @condition.to_sexp, @body.to_sexp, else_sexp]
      end
    end

    class While < Node
      attr_accessor :condition, :body, :check_first

      def initialize(line, condition, body, check_first)
        @line = line
        @condition = condition
        @body = body || NilLiteral.new(line)
        @check_first = check_first
      end

      def sexp_name
        :while
      end

      def to_sexp
        [sexp_name, @condition.to_sexp, @body.to_sexp, @check_first]
      end
    end

    class Until < While
      def sexp_name
        :until
      end
    end

    class Match < Node
      attr_accessor :pattern

      def initialize(line, pattern, flags)
        @line = line
        @pattern = RegexLiteral.new line, pattern, flags
      end

      def to_sexp
        [:match, @pattern.to_sexp]
      end
    end

    class Match2 < Node
      attr_accessor :pattern, :value

      def initialize(line, pattern, value)
        @line = line
        @pattern = pattern
        @value = value
      end

      def to_sexp
        [:match2, @pattern.to_sexp, @value.to_sexp]
      end
    end

    class Match3 < Node
      attr_accessor :pattern, :value

      def initialize(line, pattern, value)
        @line = line
        @pattern = pattern
        @value = value
      end

      def to_sexp
        [:match3, @pattern.to_sexp, @value.to_sexp]
      end
    end

    class Break < Node
      attr_accessor :value

      def initialize(line, expr)
        @line = line
        @value = expr || NilLiteral.new(line)
      end

      def jump_error(g, name)
        g.push_rubinius
        g.push_literal name
        g.send :jump_error, 1
      end

      def sexp_name
        :break
      end

      def to_sexp
        sexp = [sexp_name]
        sexp << @value.to_sexp if @value
        sexp
      end
    end

    class Next < Break
      def initialize(line, value)
        @line = line
        @value = value
      end

      def sexp_name
        :next
      end
    end

    class Redo < Break
      def initialize(line)
        @line = line
      end

      def to_sexp
        [:redo]
      end
    end

    class Retry < Break
      def initialize(line)
        @line = line
      end

      def to_sexp
        [:retry]
      end
    end

    class Return < Node
      attr_accessor :value

      def initialize(line, expr)
        @line = line
        @value = expr
        @splat = nil
      end

      def to_sexp
        sexp = [:return]
        sexp << @value.to_sexp if @value
        sexp << @splat.to_sexp if @splat
        sexp
      end
    end
  end
end
