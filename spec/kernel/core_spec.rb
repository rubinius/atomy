require "spec_helper"

require "atomy/codeloader"
require "atomy/message_structure"

module ABC; end

describe "core kernel" do
  subject { Atomy::Module.new { use(require("core")) } }

  it "implements do: notation for evaluating sequences" do
    expect(subject).to receive(:foo).and_return(1)
    expect(subject).to receive(:bar).and_return(2)
    expect(subject.evaluate(ast("do: foo, bar"), subject.compile_context)).to eq(2)
  end

  describe "macro defining" do
    it "implements a macro-defining macro" do
      subject.evaluate(ast("macro(1): '2"), subject.compile_context)
      expect(subject.evaluate(ast("1"))).to eq(2)
    end

    it "closes over its scope" do
      subject.evaluate(seq("a = '2, macro(1): a"), subject.compile_context)
      expect(subject.evaluate(ast("1"))).to eq(2)
    end
  end

  describe "pattern defining" do
    it "provides a macro for defining patterns" do
      subject.evaluate(
        ast("pattern(42 foo(~(bar & Word))): pattern(bar)"),
        subject.compile_context,
      )

      pat = subject.evaluate(subject.pattern(ast("42 foo(fizz)")))
      expect(pat).to be_a(Atomy::Pattern::Wildcard)
    end
  end

  SpecHelpers::MESSAGE_FORMS.each do |form|
    it "implements message sending in the form '#{form}'" do
      node = ast(form)

      structure = Atomy::MessageStructure.new(node)

      receiver = Object.new
      arg_1 = Object.new
      arg_2 = Object.new
      splat_args = [Object.new, Object.new]
      proc_arg = proc {}
      block_body = Object.new
      result = Object.new

      expect(receiver).to receive(structure.name) do |*args, &blk|
        expected_args = [arg_1, arg_2][0...structure.arguments.size]
        expected_args += splat_args if structure.splat_argument

        expect(args).to eq(expected_args)

        if structure.proc_argument
          expect(blk).to eq(proc_arg)
        elsif structure.block
          if structure.block.arguments.empty?
            expect(blk.call).to eq(block_body)
          else
            expect(blk.call(1, 2)).to eq([1, 2])
          end
        end

        result
      end

      if structure.receiver
        bnd = binding
      else
        bnd = receiver.instance_eval { binding }
      end

      expect(subject.evaluate(node, bnd)).to eq(result)
    end
  end

  it "implements sending #[]" do
    expect(subject.evaluate(ast("[1, 2, 3, 4, 5] [1, 2]"))).to eq([2, 3])
  end

  it "implements nested constant notation" do
    expect(subject.evaluate(ast("Atomy Module"))).to eq(Atomy::Module)
  end

  it "implements boolean literals" do
    expect(subject.evaluate(ast("false"))).to eq(false)
    expect(subject.evaluate(ast("true"))).to eq(true)
  end

  it "implements nil literals" do
    expect(subject.evaluate(ast("nil"))).to eq(nil)
  end

  it "implements undefined literals" do
    # can't expect(undefined)
    expect(subject.evaluate(ast("_")) == undefined).to eq(true)
  end

  it "implements symbol literals for words" do
    expect(subject.evaluate(ast(".to-s"))).to eq(:to_s)
  end

  it "implements symbol literals for words ending in !" do
    expect(subject.evaluate(ast(".to-s!"))).to eq(:to_s!)
  end

  it "implements symbol literals for words ending in ?" do
    expect(subject.evaluate(ast(".to-s?"))).to eq(:to_s?)
  end

  it "implements symbol literals for constants" do
    expect(subject.evaluate(ast(".String"))).to eq(:String)
  end

  it "implements symbol literals for [] and []=" do
    expect(subject.evaluate(ast(".[]"))).to eq(:[])
    expect(subject.evaluate(ast(".[]="))).to eq(:[]=)
  end

  it "implements symbol literals for strings" do
    expect(subject.evaluate(ast(".\"abc\""))).to eq(:abc)
    expect(subject.evaluate(ast(".\"blah blah\""))).to eq(:"blah blah")
  end

  it "implements instance variable access" do
    @foo = 1
    expect(subject.evaluate(ast("@foo"))).to eq(1)
  end

  it "implements instance variable access with names ending in !" do
    instance_variable_set(:"@foo!", 1)
    expect(subject.evaluate(ast("@foo!"))).to eq(1)
  end

  it "implements instance variable access with names ending in ?" do
    instance_variable_set(:"@foo?", 1)
    expect(subject.evaluate(ast("@foo?"))).to eq(1)
  end

  it "implements class variable access" do
    subject.class_variable_set(:@@foo, 1)
    expect(subject.evaluate(ast("@@foo"), subject.compile_context)).to eq(1)
  end

  it "implements class variable access with names ending in !" do
    subject.class_variable_set(:"@@foo!", 1)
    expect(subject.evaluate(ast("@@foo!"), subject.compile_context)).to eq(1)
  end

  it "implements class variable access with names ending in ?" do
    subject.class_variable_set(:"@@foo?", 1)
    expect(subject.evaluate(ast("@@foo?"), subject.compile_context)).to eq(1)
  end

  it "implements global variable access" do
    $foo = 1
    expect(subject.evaluate(ast("$foo"))).to eq(1)
    $foo = 2
    expect(subject.evaluate(ast("$foo"))).to eq(2)
  end

  it "implements global variable access with names ending in !" do
    Rubinius::Globals[:"$foo!"] = 1
    expect(subject.evaluate(ast("$foo!"))).to eq(1)
    Rubinius::Globals[:"$foo!"] = 2
    expect(subject.evaluate(ast("$foo!"))).to eq(2)
  end

  it "implements global variable access with names ending in ?" do
    Rubinius::Globals[:"$foo?"] = 1
    expect(subject.evaluate(ast("$foo?"))).to eq(1)
    Rubinius::Globals[:"$foo?"] = 2
    expect(subject.evaluate(ast("$foo?"))).to eq(2)
  end

  it "implements capitalized variable access" do
    expect(subject.evaluate(ast("$LOAD_PATH"))).to eq($LOAD_PATH)
  end

  it "implements stringified variable access" do
    begin
      raise "hell"
    rescue
      expect($!).to_not be_nil
      expect(subject.evaluate(ast('$"!"'))).to eq($!)
    end
  end

  describe "assignment" do
    it "implements local variable assignment notation" do
      expect(subject.evaluate(seq("a = 1, a + 2"))).to eq(3)
    end

    it "assigns variables spanning evals" do
      expect(subject.evaluate(seq("a = 1"))).to eq(1)
      expect(subject.evaluate(seq("a + 2"))).to eq(3)
    end

    it "raises an error when the patterns don't match" do
      expect {
        subject.evaluate(ast("2 = 1"))
      }.to raise_error(Atomy::PatternMismatch)
    end

    it "assigns only in the innermost scope" do
      expect(subject.evaluate(seq("
        a = 1
        b = { a = 2, a } call
        [a, b]
      "))).to eq([1, 2])
    end

    it "does not zero-out already-existing values during assignment" do
      expect(subject.evaluate(seq("
        a = 1
        a = (a + 1)
        a
      "))).to eq(2)
    end

    it "does not zero-out already-existing values during assignment in a nested scope" do
      expect(subject.evaluate(seq("
        a = 1
        b = { a = (a + 1) } call
        [a, b]
      "))).to eq([1, 2])
    end

    it "can assign variables with ? at the end" do
      expect(subject.evaluate(seq("a? = 1, a? + 2"))).to eq(3)
    end

    it "can assign variables with ! at the end" do
      expect(subject.evaluate(seq("a! = 1, a! + 2"))).to eq(3)
    end

    context "with reference locals" do
      it "implements local variable assignment notation" do
        expect(subject.evaluate(seq("&a = 1, a + 2"))).to eq(3)
      end

      it "assigns variables spanning evals" do
        expect(subject.evaluate(seq("&a = 1"))).to eq(1)
        expect(subject.evaluate(seq("a + 2"))).to eq(3)
      end

      it "overrides existing locals if possible" do
        expect(subject.evaluate(seq("
          a = 1
          b = { &a = 2, a } call
          [a, b]
        "))).to eq([2, 2])
      end

      it "does not zero-out already-existing values during assignment" do
        expect(subject.evaluate(seq("
          a = 1
          &a = (a + 1)
          { &a = (a + 1) } call
          a
        "))).to eq(3)
      end

      it "can set variables with ? at the end" do
        expect(subject.evaluate(seq("&a? = 1, a? + 2"))).to eq(3)
      end

      it "can set variables with ! at the end" do
        expect(subject.evaluate(seq("&a! = 1, a! + 2"))).to eq(3)
      end
    end
  end

  describe "blocks" do
    it "implements block literals" do
      blk = subject.evaluate(ast("{ 1 + 2 }"))
      expect(blk).to be_kind_of(Proc)
      expect(blk.call).to eq(3)
    end

    it "implements block literals with arguments" do
      blk = subject.evaluate(ast("[a, b]: a + b"))
      expect(blk).to be_kind_of(Proc)
      expect(blk.call(1, 2)).to eq(3)
    end

    it "constructs blocks that close over their scope" do
      blk = subject.evaluate(seq("a = 1, [b]: a + b"))
      expect(blk).to be_kind_of(Proc)
      expect(blk.call(2)).to eq(3)
    end

    it "pattern-matches block arguments" do
      blk = subject.evaluate(seq("[a, `(1 + ~b)]: [a, b value]"))
      expect(blk).to be_kind_of(Proc)
      expect(blk.call(1, ast("1 + 2"))).to eq([1, 2])
    end

    it "implements block literals with block arguments" do
      blk = subject.evaluate(ast("&abc { abc call + 1 }"))
      expect(blk.call { 41 }).to eq(42)
    end

    it "implements block literals with arguments and block arguments" do
      blk = subject.evaluate(ast("[a, b] &abc { abc call + (a + b) }"))
      expect(blk.call(1, 2) { 39 }).to eq(42)
    end
  end

  it "implements toplevel constant access" do
    Thread.current[:binding] = nil

    module XYZ
      module ABC
      end

      Thread.current[:binding] = binding
    end

    bnd = Thread.current[:binding]

    expect(subject.evaluate(ast("//ABC"), bnd)).to eq(::ABC)
  end
end
