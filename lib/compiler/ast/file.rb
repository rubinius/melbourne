# -*- encoding: us-ascii -*-

module Rubinius
  module AST
    class File < Node
      def to_sexp
        [:file]
      end
    end
  end
end
