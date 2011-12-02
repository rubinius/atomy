module Atomy
  module AST
    class Block < Rubinius::AST::Iter
      include NodeLike
      extend SentientNode

      children [:contents], [:arguments], :block?
      generate

      def body
        BlockBody.new @line, @contents
      end

      alias :caller :body

      def bytecode(g)
        pos(g)

        state = g.state
        state.scope.nest_scope self

        arguments = BlockArguments.new @arguments
        blk = new_block_generator g, arguments

        blk.push_state self
        blk.state.push_super state.super
        blk.state.push_eval state.eval

        blk.state.push_name blk.name

        # Push line info down.
        pos(blk)

        if @block
          blk.push_block_arg
          @block.to_pattern.deconstruct(blk)
        end

        arguments.bytecode(blk)

        blk.state.push_block
        blk.push_modifiers
        blk.break = nil
        blk.next = nil
        blk.redo = blk.new_label
        blk.redo.set!

        too_few = blk.new_label
        done = blk.new_label

        blk.passed_arg(arguments.required_args - 1)
        blk.gif too_few

        body.compile(blk)
        blk.goto done

        too_few.set!
        blk.push_self
        blk.push_cpath_top
        blk.find_const :ArgumentError
        blk.push_literal "wrong number of arguments"
        blk.send :new, 1
        blk.send :raise, 1, true

        done.set!

        blk.pop_modifiers
        blk.state.pop_block
        blk.ret
        blk.close
        blk.pop_state

        blk.splat_index = arguments.splat_index
        blk.local_count = local_count
        blk.local_names = local_names

        g.create_block blk

        g.push_cpath_top
        g.find_const :Proc
        g.swap
        g.send :__from_block__, 1
      end
    end

    class BlockArguments
      attr_reader :arguments

      def initialize(args)
        @arguments = args.collect(&:to_pattern)
      end

      def bytecode(g)
        return if @arguments.empty?

        g.cast_for_splat_block_arg
        @arguments.each do |a|
          if a.kind_of?(Patterns::Splat)
            a.pattern.deconstruct(g)
            return
          else
            g.shift_array
            a.match(g)
          end
        end
        g.pop
      end

      def local_names
        @arguments.collect { |a| a.local_names }.flatten
      end

      def size
        @arguments.size
      end

      def locals
        local_names.size
      end

      def required_args
        @arguments.reject { |a|
          a.is_a?(Patterns::Default) || a.is_a?(Patterns::Splat) ||
            a.is_a?(Patterns::BlockPass)
        }.size
      end

      def total_args
        if splat_index
          size - 1
        else
          size
        end
      end

      def splat_index
        @arguments.each do |a,i|
          return i if a.kind_of?(Patterns::Splat)
        end
        nil
      end

      def post_args
        0
      end
    end

    class BlockBody < Node
      children [:expressions]
      generate

      def empty?
        @expressions.empty?
      end

      def bytecode(g)
        pos(g)

        g.push_nil if empty?

        @expressions.each_with_index do |node,idx|
          g.pop unless idx == 0
          node.compile(g)
        end
      end
    end
  end
end
