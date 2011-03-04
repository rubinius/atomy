module Atomo
  module AST
    class Primitive < Node
      attr_reader :value

      def initialize(line, value)
        @value = value
        @line = line
      end

      def ==(b)
        b.kind_of?(Primitive) and \
        @value == b.value
      end

      def bytecode(g)
        pos(g)

        # TODO: `(~#true) will break here
        case @value
        when :true, :false, :self, :nil, Integer
          g.push @value
        else
          g.push_literal @value
        end
      end
    end
  end
end
