require "atomy/method"

class Object
  attr_reader :atomy_methods

  def atomy_methods
    @atomy_methods ||= {}
  end
end

module Atomy
  module_function

  def define_branch(binding, name, receiver, arguments, locals, &body)
    target =
      if receiver
        receiver.target
      else
        binding.constant_scope.for_method_definition
      end

    methods = target.atomy_methods
    method = methods[name] ||= Atomy::Method.new(name)

    branch = method.add_branch(receiver, arguments, body.block, locals)

    Rubinius.add_method(name, method.build, target, :public)
  end
end
