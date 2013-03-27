require "atomy/pattern"

require "atomy/node/meta"


class Atomy::Pattern
  class QuasiQuote < self
    attr_reader :node

    def self.make(mod, node)
      new(Constructor.new(mod).go(node))
    end

    def initialize(node)
      @node = node
    end

    def matches?(gen, mod)
      mismatch = gen.new_label
      done = gen.new_label

      Matcher.new(gen, mod, mismatch).go(@node)

      gen.push_true
      gen.goto done

      mismatch.set!
      gen.push_false

      done.set!
    end

    def deconstruct(gen, mod, locals = {})
      Deconstructor.new(gen, mod).go(@node)
    end

    private

    class Walker
      def initialize(gen, mod)
        @depth = 1
        @gen = gen
        @module = mod
      end

      def go(x, mismatch = nil)
        if mismatch
          old, @mismatch = @mismatch, mismatch
        end

        x.accept(self)
      ensure
        @mismatch = old if mismatch
      end

      def visit_quasiquote(qq)
        @depth += 1
        visit(qq)
        @depth -= 1
      end

      def visit_unquote(x)
        @depth -= 1

        res =
          if @depth == 0
            unquote(x)
          else
            visit(x)
          end

        @depth += 1

        res
      end

      def unquote(_)
        raise NotImplementedError
      end

      def push_literal(x)
        case x
        when Array
          x.each { |v| push_literal(v) }
          @gen.make_array(x.size)
        when String
          @gen.push_literal(x)
          @gen.string_dup
        else
          @gen.push_literal(x)
        end
      end
    end

    class Constructor < Walker
      def initialize(mod)
        @module = mod
        @depth = 1
      end

      def go(x)
        x.accept(self)
      end

      def visit(x)
        x.through do |v|
          go(v)
        end
      end

      def unquote(x)
        x.through { |p| @module.pattern(p) }
      end
    end

    class Matcher < Walker
      def initialize(gen, mod, mis)
        super(gen, mod)
        @mismatch = mis
      end

      def match_kind(x, mismatch)
        @gen.dup
        push_class(@gen, x.class)
        @gen.swap
        @gen.kind_of
        @gen.gif mismatch
      end

      def push_class(gen, klass)
        gen.push_cpath_top
        klass.name.split("::").each do |name|
          gen.find_const(name.to_sym)
        end
      end

      def match_attribute(n, val, mismatch)
        @gen.dup
        @gen.send(n, 0)
        push_literal(val)
        @gen.send(:==, 1)
        @gen.gif mismatch
      end

      def match_required(c, pat, mismatch)
        @gen.dup
        @gen.send(c, 0)
        go(pat, mismatch)
      end

      def match_many(c, pats, popmis, popmis2)
        @gen.dup
        @gen.send c, 0

        @gen.dup
        @gen.send :size, 0
        @gen.push_int(pats.size)
        @gen.send(:==, 1)
        @gen.gif popmis2

        pats.each do |pat|
          @gen.shift_array
          go(pat, popmis2)
        end

        @gen.pop
      end

      # effect on the stack: pop
      def visit(x)
        popmis = @gen.new_label
        popmis2 = @gen.new_label
        done = @gen.new_label

        match_kind(x, popmis)

        x.each_attribute do |a, val|
          match_attribute(a, val, popmis)
        end

        x.each_child do |c, val|
          if val.is_a?(Array)
            match_many(c, val, popmis, popmis2)
          else
            match_required(c, val, popmis)
          end
        end

        @gen.goto done

        popmis2.set!
        @gen.pop

        popmis.set!
        @gen.pop
        @gen.goto @mismatch

        done.set!
        @gen.pop
      end

      def unquote(x)
        x.node.matches?(@gen, @module)
        @gen.gif @mismatch
      end
    end

    class Deconstructor < Walker
      def unquote(x)
        @depth -= 1

        if @depth == 0
          x.node.deconstruct(@gen, @module)
        else
          visit(x)
        end

        @depth += 1
      end

      def visit(x)
        x.each_child do |c, val|
          if val.is_a?(Array)
            visit_many(c, val)
          else
            visit_one(c, val)
          end
        end
      end

      def visit_one(c, pat)
        @gen.dup
        @gen.send(c, 0)
        go(pat)
        @gen.pop
      end

      def visit_many(c, pats)
        return if pats.empty?

        @gen.dup
        @gen.send(c, 0)

        pats.each do |pat|
          @gen.shift_array
          go(pat)
        end

        # pop empty array
        @gen.pop

        @gen.pop
      end
    end
  end
end
