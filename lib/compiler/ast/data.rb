# -*- encoding: us-ascii -*-

module Rubinius
  module AST
    class EndData < Node
      attr_accessor :data

      def initialize(offset, body)
        @offset = offset
        @body = body || NilLiteral.new(1)
      end
    end
  end
end
