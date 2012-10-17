# -*- encoding: us-ascii -*-

module Rubinius
  class Compiler
    module LocalVariables
      def variables
        @variables ||= {}
      end

      def local_count
        variables.size
      end

      def local_names
        names = []
        eval_names = []
        variables.each_pair do |name, var|
          case var
          when EvalLocalVariable
            eval_names << name
          when LocalVariable
            names[var.slot] = name
          # We ignore NestedLocalVariables because they're
          # tagged as existing only in their source scope.
          end
        end
        names += eval_names
      end

      def allocate_slot
        variables.size
      end
    end

    class LocalVariable
      attr_reader :slot

      def initialize(slot)
        @slot = slot
      end

      def reference
        LocalReference.new @slot
      end

      def nested_reference
        NestedLocalReference.new @slot
      end
    end

    class NestedLocalVariable
      attr_reader :depth, :slot

      def initialize(depth, slot)
        @depth = depth
        @slot = slot
      end

      def reference
        NestedLocalReference.new @slot, @depth
      end

      alias_method :nested_reference, :reference
    end

    class EvalLocalVariable
      attr_reader :name

      def initialize(name)
        @name = name
      end

      def reference
        EvalLocalReference.new @name
      end

      alias_method :nested_reference, :reference
    end

    class LocalReference
      attr_reader :slot

      def initialize(slot)
        @slot = slot
      end
    end

    class NestedLocalReference
      attr_accessor :depth
      attr_reader :slot

      def initialize(slot, depth=0)
        @slot = slot
        @depth = depth
      end
    end

    class EvalLocalReference

      # Ignored, but simplifies duck-typing references
      attr_accessor :depth

      def initialize(name)
        @name = name
        @depth = 0
      end
    end
  end
end
