module Atomy
  def self.segments(args)
    req = args.reject { |a| a.kind_of?(Patterns::BlockPass) || a.kind_of?(Patterns::Splat) || a.kind_of?(Patterns::Default) }
    dfs = args.select { |a| a.kind_of?(Patterns::Default) }
    spl = args.select { |a| a.kind_of?(Patterns::Splat) }[0]
    blk = args.select { |a| a.kind_of?(Patterns::BlockPass) }[0]
    [req, dfs, spl, blk]
  end

  def self.build_method(name, branches, is_macro = false, file = :dynamic, line = 1)
    g = Rubinius::Generator.new
    g.name = name.to_sym
    g.file = file.to_sym
    g.set_line Integer(line)

    done = g.new_label
    mismatch = g.new_label

    g.push_state Rubinius::AST::ClosedScope.new(line)

    g.state.push_name name

    block_offset = is_macro ? 1 : 0

    args = 0
    min_reqs = nil
    reqs = 0
    defs = 0
    g.local_names = branches.collect do |pats, meth|
      segs = segments(pats[1])
      min_reqs ||= segs[0].size
      min_reqs = [min_reqs, segs[0].size].min
      reqs = [reqs, segs[0].size].max
      defs = [defs, segs[1].size].max
      args = [reqs + defs, args].max
      pats[0].local_names + pats[1].collect { |p| p.local_names }.flatten
    end.flatten.uniq

    args += block_offset

    args.times do |n|
      g.local_names.unshift("arg:" + n.to_s)
    end

    locals = {}
    g.local_names.each do |n|
      locals[n] = g.state.scope.new_local(n).reference
    end

    g.total_args = args
    g.required_args = min_reqs
    g.local_count = args + g.local_names.size

    g.push_self
    branches.each do |pats, meth|
      recv = pats[0]
      reqs, defs, splat, block = segments(pats[1])

      g.splat_index = (block_offset + reqs.size + defs.size) if splat

      skip = g.new_label
      argmis = g.new_label

      if reqs.size > min_reqs
        g.passed_arg(reqs.size - 1)
        g.gif skip
      end

      g.dup
      recv.matches?(g) # TODO: skip kind_of matches
      g.gif skip

      if recv.bindings > 0
        g.push_self
        recv.deconstruct(g, locals)
      end

      if is_macro && block
        g.push_local(0)
        block.pattern.deconstruct(g, locals)
      end

      if splat
        g.push_local(block_offset + reqs.size + defs.size)
        splat.pattern.deconstruct(g)
      end

      unless reqs.empty?
        reqs.each_with_index do |a, i|
          n = i + block_offset
          g.push_local(n)

          if a.bindings > 0
            g.dup
            a.matches?(g)
            g.gif argmis
            a.deconstruct(g, locals)
          else
            a.matches?(g)
            g.gif skip
          end
        end
      end

      unless defs.empty?
        defs.each_with_index do |d, i|
          passed = g.new_label
          decons = g.new_label

          num = reqs.size + i
          g.passed_arg num
          g.git passed

          d.default.bytecode(g)
          g.set_local num
          g.goto decons

          passed.set!
          g.push_local num

          decons.set!
          d.deconstruct(g)
        end
      end

      if !is_macro && block
        g.push_block_arg
        block.deconstruct(g)
      end

      meth.bytecode(g)
      g.goto done

      argmis.set!
      g.pop

      skip.set!
    end

    g.invoke_primitive :vm_check_super_callable, 0
    g.gif mismatch

    g.push_block
    if g.state.super?
      g.zsuper g.state.super.name
    else
      g.zsuper nil
    end
    g.goto done

    mismatch.set!
    g.push_self
    g.push_const :MethodFail
    g.push_literal name
    g.send :new, 1
    g.allow_private
    g.send :raise, 1

    done.set!
    g.state.pop_name
    g.ret
    g.close
    g.pop_state
    g.use_detected
    g.encode

    g.package Rubinius::CompiledMethod
  end

  def self.add_method(target, name, branches, static_scope, visibility = :public, is_macro = false)
    cm = build_method(name, branches, is_macro)

    cm.scope = static_scope

    Rubinius.add_method name, cm, target, visibility
  end

  def self.compare_heads(xs, ys)
    return 1 if xs.size > ys.size
    return -1 if xs.size < ys.size

    xs.zip(ys) do |x, y|
      cmp = x <=> y
      return cmp unless cmp == 0
    end

    0
  end

  def self.equivalent?(xs, ys)
    xs.zip(ys) do |x, y|
      return false unless x =~ y
    end

    true
  end

  def self.insert_method(new, branches)
    (nr, na), nb = new
    if nr.respond_to?(:<=>)
      branches.each_with_index do |branch, i|
        (r, a), b = branch
        case compare_heads([nr] + na, [r] + a)
        when 1
          return branches.insert(i, new)
        when 0
          if equivalent?([nr] + na, [r] + a)
            branches[i] = new
            return branches
          end
        end
      end
    end

    branches << new
  end
end
