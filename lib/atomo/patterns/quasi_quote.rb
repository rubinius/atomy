module Atomo::Patterns
  class QuasiQuote < Pattern
    def initialize(x)
      @expression = x
    end

    def construct(g)
      get(g)
      @expression.construct(g, nil)
      g.send :new, 1
    end

    def ==(b)
      b.kind_of?(QuasiQuote) and \
      @expression == b.expression
    end

    def target(g)
      # TODO
      Constant.new(-1, @expression.class.name.split("::")).target(g)
    end

    def matches?(g)
      mismatch = g.new_label
      done = g.new_label

      them = g.new_stack_local
      g.set_stack_local them
      g.pop

      where = []
      depth = 0
      @expression.recursively(
        proc { |n, c|
          where << c if c
          n.kind_of?(Atomo::AST::Unquote) || n.kind_of?(Atomo::AST::QuasiQuote)
        },
        proc { where.pop }
      ) do |e|
        if e.kind_of?(Atomo::AST::Unquote)
          if depth == 0
            g.push_stack_local them
            where.each do |a|
              g.send a, 0
            end
            Atomo::Patterns.from_node(e.expression).matches?(g)
            g.gif mismatch
            next e
          end
          depth -= 1
        end

        if e.kind_of?(Atomo::AST::QuasiQuote)
          depth += 1
        end

        e.get(g)
        g.push_stack_local them
        where.each do |a|
          g.send a, 0
        end
        g.kind_of
        g.gif mismatch

        next unless e.bottom?

        e.construct(g)
        g.push_stack_local them
        where.each do |a|
          g.send a, 0
        end
        g.send :==, 1
        g.gif mismatch
        e
      end

      g.push_true
      g.goto done

      mismatch.set!
      g.push_false

      done.set!
    end

    def deconstruct(g, locals = {})
      them = g.new_stack_local
      g.set_stack_local them
      g.pop

      where = []
      depth = 0
      @expression.recursively(
        proc { |n, c|
          where << c if c
          n.kind_of?(Atomo::AST::Unquote) || n.kind_of?(Atomo::AST::QuasiQuote)
        },
        proc { where.pop }
      ) do |e|
        if e.kind_of?(Atomo::AST::Unquote)
          if depth == 0
            g.push_stack_local them
            where.each do |a|
              g.send a, 0
            end
            Atomo::Patterns.from_node(e.expression).deconstruct(g, locals)
            next e
          end

          depth -= 1
        end

        if e.kind_of?(Atomo::AST::QuasiQuote)
          depth += 1
        end

        e
      end
    end
  end
end