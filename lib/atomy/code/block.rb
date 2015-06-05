module Atomy
  module Code
    class Block
      def initialize(body, args = [])
        @body = body
        @arguments = args
      end

      def bytecode(gen, mod)
        blk = build_block(gen.state.scope, mod)

        gen.push_cpath_top
        gen.find_const :Proc
        gen.create_block(blk)
        gen.send(:__from_block__, 1)
        gen.dup
        gen.send(:lambda_style!, 0)
        gen.pop
      end

      private

      def build_block(scope, mod)
        Atomy::Compiler.generate(mod.file) do |blk|
          # close over the outer scope
          blk.state.scope.parent = scope

          # for now, only allow a fixed set of arguments
          blk.required_args = blk.total_args = @arguments.size

          # this bubbles up to Proc#arity and BlockEnvironment, though it
          # doesn't appear to change actual behavior of the block
          blk.arity = @arguments.size

          # discard extra arguments
          blk.splat_index = @arguments.size

          # create a local for each argument name
          @arguments.each.with_index do |a, i|
            blk.state.scope.new_local(:"arg:#{i}")
          end

          # local for discarded splat args
          blk.state.scope.new_local(:"arg:extra")

          # pattern-match all args
          @arguments.each.with_index do |a, i|
            Assign.new(a, Variable.new(:"arg:#{i}")).bytecode(blk, mod)
          end

          # build the block's body
          mod.compile(blk, @body)
        end
      end
    end
  end
end