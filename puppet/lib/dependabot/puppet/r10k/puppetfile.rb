# frozen_string_literal: true

require "dependabot/puppet/r10k/module/base"
require "dependabot/puppet/r10k/module/forge"
require "dependabot/puppet/r10k/module/git"
require "dependabot/puppet/r10k/module/invalid"
require "dependabot/puppet/r10k/module/local"
require "dependabot/puppet/r10k/module/svn"

module Dependabot
  module Puppet
    module Puppetfile
      module R10K
        PUPPETFILE_MONIKER ||= 'Puppetfile'

        class Puppetfile
          attr_reader :modules

          def load!(puppetfile_contents)
            @modules = []

            if defined?(RubyVM::AbstractSyntaxTree)
              parser = AST.new(self)
              parser.parse(puppetfile_contents)
            else
              puppetfile = DSL.new(self)
              puppetfile.instance_eval(puppetfile_contents, PUPPETFILE_MONIKER)
            end
          end

          def add_module(name, args)
            @modules << Module.from_puppetfile(name, args)
          end

          class DSL
            def initialize(parent)
              @parent = parent
            end

            # @param [String] name
            # @param [*Object] args
            def mod(name, args = nil)
              @parent.add_module(name, args)
            end

            # @param [String] forge
            def forge(_location)
            end

            # @param [String] moduledir
            def moduledir(_location)
            end

            def method_missing(method, *_args) # rubocop:disable Style/MethodMissingSuper, Style/MissingRespondToMissing
              raise NoMethodError, format("Unknown method '%<method>s'", method: method)
            end
          end

          class AST
            def initialize(parent)
              @parent = parent
            end

            def parse(puppetfile)
              root = nil
              begin
                root = RubyVM::AbstractSyntaxTree.parse(puppetfile)
              rescue NameError => e
                raise "Cannot parse Puppetfile directly on Ruby version #{RUBY_VERSION}"
              end
              traverse(root)
            end

            def traverse(node)
              begin
                if node.type == :FCALL
                  name = node.children.first
                  args = node.children.last.children.map do |item|
                    next if item.nil?

                    case item.type
                    when :HASH
                      Hash[*item.children.first.children.compact.map {|n| n.children.first }]
                    else
                      item.children.first
                    end
                  end.compact

                  case name
                  when :mod
                    @parent.add_module(args.shift, *args)
                  when :forge, :moduledir
                    # noop
                  else
                    # Should we log unexpected Ruby code?
                  end
                end

                node.children.each do |n|
                  next unless n.is_a? RubyVM::AbstractSyntaxTree::Node

                  traverse(n)
                end
              rescue => e
                puts e.message
              end
            end
          end

        end
      end
    end
  end
end
