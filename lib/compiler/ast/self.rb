# -*- encoding: us-ascii -*-

module Rubinius
  module AST
    class Self < Node
      def value_defined(g, f)
        g.push :self
      end

      def to_sexp
        [:self]
      end
    end
  end
end
