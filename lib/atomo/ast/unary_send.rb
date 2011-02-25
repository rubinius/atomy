module Atomo
  module AST
    class UnarySend < AST::Node
      Atomo::Parser.register self

      def self.rule_name
        "unary_send"
      end

      def initialize(receiver, name, arguments, block = nil, privat = false)
        @receiver = receiver
        @method_name = name
        @arguments = arguments
        @block = block unless block == []
        @private = privat
        @line = 1 # TODO
      end

      attr_reader :receiver, :method_name, :arguments

      def self.grammar(g)
        g.unary_args =
          g.seq(
            "(", g.t(:some_expressions), ")"
          )

        g.unary_send =
          g.seq(
            :unary_send, :sig_sp, :identifier, g.notp(":"), g.maybe(:unary_args),
            g.maybe(g.seq(:sp, g.t(:block)))
          ) do |v, _, n, _, x, b|
            UnarySend.new(v,n,x,b)
          end | g.seq(
            :level1, :sig_sp, :identifier, g.notp(":"), g.maybe(:unary_args),
            g.maybe(g.seq(:sp, g.t(:block)))
          ) do |v, _, n, _, x, b|
            UnarySend.new(v,n,x,b)
          end | g.seq(
            :identifier, :unary_args,
            g.maybe(g.seq(:sp, g.t(:block)))
          ) do |n, x, b|
            UnarySend.new(Primitive.new(:self),n,x,b,true)
          end
      end

      def bytecode(g)
        pos(g)

        @receiver.bytecode(g)
        block = @block
        if not block and @arguments.last.kind_of? Block
          block = @arguments.pop
        end

        @arguments.each do |a|
          a.bytecode(g)
        end

        if block
          block.bytecode(g)
          g.send_with_block @method_name.to_sym, @arguments.size, @private
        else
          g.send @method_name.to_sym, @arguments.size, @private
        end
      end
    end
  end
end
