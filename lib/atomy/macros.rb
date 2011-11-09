module Atomy::Macro
  module Helpers
    def word(name, line = 0)
      Atomy::AST::Word.new(line, name.to_s)
    end

    # generate symbols
    def names(num = 0, &block)
      num = block.arity if block

      as =
        Hamster.stream {
          word("s:" + Atomy::Macro::Environment.salt!.to_s)
        }.take(num)

      if block
        block.call(*as.to_a)
      else
        as
      end
    end
  end

  class Environment
    @@salt = 0
    @@let = {}

    class << self
      def let
        @@let
      end

      def salt
        @@salt
      end

      def salt!(n = 1)
        @@salt += n
      end
    end
  end

  def self.register(target, pattern, body, file = :macro, let = false)
    name = let ? :"_let#{Environment.salt!}" : :_expand

    Atomy.define_method(
      target,
      name,
      Atomy::Method.new(
        pattern,
        Atomy::AST::Send.new(
          body.line,
          Atomy::AST::Send.new(
            body.line,
            body,
            [],
            "to_node"
          ),
          [],
          "expand"
        ),
        Rubinius::StaticScope.new(Atomy::AST),
        [], [], nil, nil,
        file
      ),
      :public
    )

    if let
      Environment.let[target] ||= []
      Environment.let[target] << name
    end

    name
  end
end