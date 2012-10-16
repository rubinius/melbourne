# -*- encoding: us-ascii -*-

module Rubinius
  module AST
    class Encoding < Node
      attr_accessor :name

      def initialize(line, name)
        @line = line
        @name = name
      end

      def to_sexp
        [:encoding, @name]
      end
    end
  end
end
