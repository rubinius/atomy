module Atomo
  module AST
    class Match < Node
      attr_reader :target, :body

      def initialize(target, body)
        @target = target
        @body = body
        @line = 1 # TODO
      end

      def recursively(stop = nil, &f)
        return f.call self if stop and stop.call(self)

        f.call Match.new(
          target.recursively(stop, &f),
          body.recursively(stop, &f)
        )
      end

      def construct(g, d)
        get(g)
        @target.construct(g, d)
        @body.construct(g, d)
        g.send :new, 2
      end

      def bytecode(g)
        pos(g)

        done = g.new_label

        @target.bytecode(g)

        @body.body.expressions.each do |e|
          skip = g.new_label

          pat = Patterns.from_node(e.lhs)
          exp = e.rhs

          g.dup
          pat.matches?(g)
          g.gif skip

          pat.deconstruct(g)
          exp.bytecode(g)
          g.goto done

          skip.set!
        end

        g.pop
        g.push_nil

        done.set!
      end
    end
  end
end