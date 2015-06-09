require "atomy"
require "spec_helper"

require "atomy/bootstrap"
require "atomy/code/constant"
require "atomy/module"
require "atomy/pattern/equality"
require "atomy/pattern/kind_of"
require "atomy/pattern/wildcard"

describe Atomy do
  describe ".define_branch" do
    def wildcard(name = nil)
      Atomy::Pattern::Wildcard.new(name)
    end

    def equality(value)
      Atomy::Pattern::Equality.new(value)
    end

    def kind_of_pat(klass)
      Atomy::Pattern::KindOf.new(klass)
    end

    class SomeTarget
    end

    let(:target) { Atomy::Module.new }

    context "when the pattern has a target" do
      it "defines the method branch on the target" do
        described_class.define_branch(
          binding,
          :foo,
          Atomy::Method::Branch.new(kind_of_pat(SomeTarget), [], nil, nil, []) { 2 },
        )

        expect(SomeTarget.new.foo).to eq(2)
        expect { Object.new.foo }.to raise_error
      end
    end

    context "when the pattern does not have a target" do
      it "defines the method branch on the module definition target" do
        def_binding = nil

        foo = Module.new { def_binding = binding }

        described_class.define_branch(
          def_binding,
          :foo,
          Atomy::Method::Branch.new(nil, [], nil, nil, []) { 2 },
        )

        bar = Class.new { include foo }

        expect(bar.new.foo).to eq(2)
      end
    end

    describe "pattern-matching" do
      it "pattern-matches the message with the given pattern" do
        described_class.define_branch(
          target.module_eval { binding },
          :foo,
          Atomy::Method::Branch.new(nil, [equality(0)], nil, nil, []) { 42 },
        )

        expect(target.foo(0)).to eq(42)
        expect { target.foo(1) }.to raise_error(Atomy::MessageMismatch)
      end

      it "extends methods with branches for different patterns" do
        described_class.define_branch(
          target.module_eval { binding },
          :foo,
          Atomy::Method::Branch.new(nil, [equality(0)], nil, nil, []) { 42 },
        )

        described_class.define_branch(
          target.module_eval { binding },
          :foo,
          Atomy::Method::Branch.new(nil, [equality(1)], nil, nil, []) { 43 },
        )

        expect(target.foo(0)).to eq(42)
        expect(target.foo(1)).to eq(43)
      end

      it "does not match if not enough arguments were given" do
        described_class.define_branch(
          target.module_eval { binding },
          :foo,
          Atomy::Method::Branch.new(nil, [equality(1), wildcard], nil, nil, []) { 42 },
        )

        described_class.define_branch(
          target.module_eval { binding },
          :foo,
          Atomy::Method::Branch.new(nil, [equality(0)], nil, nil, []) { 43 },
        )

        expect { target.foo(1) }.to raise_error(Atomy::MessageMismatch)
      end

      it "does not match if too many arguments were given and there is no splat" do
        described_class.define_branch(
          target.module_eval { binding },
          :foo,
          Atomy::Method::Branch.new(nil, [equality(1), wildcard], nil, nil, []) { 42 },
        )

        described_class.define_branch(
          target.module_eval { binding },
          :foo,
          Atomy::Method::Branch.new(nil, [equality(2), wildcard, wildcard], nil, nil, []) { 43 },
        )

        expect { target.foo(1, 2, 3) }.to raise_error(Atomy::MessageMismatch)
      end

      it "pattern-matches on the splat argument" do
        described_class.define_branch(
          target.module_eval { binding },
          :foo,
          Atomy::Method::Branch.new(nil, [wildcard], equality([2, 3]), nil, []) { :a },
        )

        described_class.define_branch(
          target.module_eval { binding },
          :foo,
          Atomy::Method::Branch.new(nil, [wildcard], wildcard, nil, []) { :b },
        )

        expect(target.foo(1, 2, 3)).to eq(:a)
        expect(target.foo(2, 2, 3)).to eq(:a)
        expect(target.foo(2, 2, 3, 4)).to eq(:b)
        expect(target.foo(1)).to eq(:b)
        expect { target.foo }.to raise_error(ArgumentError)
      end

      it "captures the splat argument" do
        described_class.define_branch(
          target.module_eval { binding },
          :foo,
          Atomy::Method::Branch.new(
            nil,
            [wildcard(:x)],
            wildcard(:ys),
            nil,
            [:x, :ys],
          ) { |x, ys| [x, ys] },
        )

        expect(target.foo(1, 2, 3)).to eq([1, [2, 3]])
      end

      it "pattern-matches on the block argument" do
        described_class.define_branch(
          target.module_eval { binding },
          :foo,
          Atomy::Method::Branch.new(nil, [], nil, equality(nil), []) { :not_provided },
        )

        described_class.define_branch(
          target.module_eval { binding },
          :foo,
          Atomy::Method::Branch.new(nil, [], nil, wildcard, []) { :provided },
        )

        expect(target.foo {}).to eq(:provided)
        expect(target.foo).to eq(:not_provided)
      end

      it "captures the block argument" do
        described_class.define_branch(
          target.module_eval { binding },
          :foo,
          Atomy::Method::Branch.new(nil, [], nil, wildcard(:x), [:x]) { |x| x.call },
        )

        expect(target.foo { 42 }).to eq(42)
      end

      context "when a wildcard method is defined after a specific one" do
        it "does not clobber the more specific one, as it was defined first" do
          described_class.define_branch(
            target.module_eval { binding },
            :foo,
            Atomy::Method::Branch.new(nil, [equality(0)], nil, nil, []) { 0 },
          )

          described_class.define_branch(
            target.module_eval { binding },
            :foo,
            Atomy::Method::Branch.new(nil, [wildcard], nil, nil, []) { 42 },
          )

          expect(target.foo(0)).to eq(0)
          expect(target.foo(1)).to eq(42)
        end
      end

      context "when a wildcard method is defined before a specific one" do
        it "clobbers later definitions" do
          described_class.define_branch(
            target.module_eval { binding },
            :foo,
            Atomy::Method::Branch.new(nil, [wildcard], nil, nil, []) { 42 },
          )

          described_class.define_branch(
            target.module_eval { binding },
            :foo,
            Atomy::Method::Branch.new(nil, [equality(0)], nil, nil, []) { 0 },
          )

          expect(target.foo(0)).to eq(42)
          expect(target.foo(1)).to eq(42)
        end
      end

      context "when pattern-matching fails" do
        context "and a method is defined on super" do
          it "sends it to super" do
            base = Class.new
            sub = Class.new(base)

            described_class.define_branch(
              base.class_eval { binding },
              :foo,
              Atomy::Method::Branch.new(nil, [equality(0)], nil, nil, []) { 0 },
            )

            described_class.define_branch(
              sub.class_eval { binding },
              :foo,
              Atomy::Method::Branch.new(nil, [equality(1)], nil, nil, []) { 1 },
            )

            expect(sub.new.foo(0)).to eq(0)
            expect(sub.new.foo(1)).to eq(1)
          end
        end

        context "and a method is NOT defined on super" do
          it "fails with MessageMismatch" do
            described_class.define_branch(
              target.module_eval { binding },
              :foo,
              Atomy::Method::Branch.new(nil, [equality(0)], nil, nil, []) { 0 },
            )

            expect { target.foo(1) }.to raise_error(Atomy::MessageMismatch)
          end
        end
      end
    end
  end
end
