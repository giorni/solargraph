module Solargraph
  class Source
    module NodeMethods
      module_function

      # @return [String]
      def unpack_name(node)
        pack_name(node).join("::")
      end

      # @return [Array<String>]
      def pack_name(node)
        parts = []
        if node.kind_of?(AST::Node)
          node.children.each { |n|
            if n.kind_of?(AST::Node)
              if n.type == :cbase
                parts = [''] + pack_name(n)
              else
                parts += pack_name(n)
              end
            else
              parts.push n unless n.nil?
            end
          }
        end
        parts
      end

      # @return [String]
      def const_from node
        if node.kind_of?(AST::Node) and node.type == :const
          result = ''
          unless node.children[0].nil?
            result = const_from(node.children[0])
          end
          if result == ''
            result = node.children[1].to_s
          else
            result = result + '::' + node.children[1].to_s
          end
          result
        else
          nil
        end
      end

      # @return [String]
      def infer_literal_node_type node
        return nil unless node.kind_of?(AST::Node)
        if node.type == :str or node.type == :dstr
          return 'String'
        elsif node.type == :array
          return 'Array'
        elsif node.type == :hash
          return 'Hash'
        elsif node.type == :int
          return 'Integer'
        elsif node.type == :float
          return 'Float'
        elsif node.type == :sym
          return 'Symbol'
        elsif node.type == :regexp
          return 'Regexp'
        # @todo Maybe ignore nils
        # elsif node.type == :nil
        #   return 'NilClass'
        end
        nil
      end

      # Get a call signature from a node.
      # The result should be a string in the form of a method path, e.g.,
      # String.new or variable.method.
      #
      # @return [String]
      def resolve_node_signature node
        result = drill_signature node, ''
        return nil if result.empty?
        result
      end

      def get_node_start_position(node)
        Position.new(node.loc.line, node.loc.column)
      end

      def get_node_end_position(node)
        Position.new(node.loc.last_line, node.loc.last_column)
      end

      def drill_signature node, signature
        return signature unless node.kind_of?(AST::Node)
        if node.type == :const or node.type == :cbase
          unless node.children[0].nil?
            signature += drill_signature(node.children[0], signature)
          end
          signature += '::' unless signature.empty?
          signature += node.children[1].to_s
        elsif node.type == :lvar or node.type == :ivar or node.type == :cvar
          signature += '.' unless signature.empty?
          signature += node.children[0].to_s
        elsif node.type == :send
          unless node.children[0].nil?
            signature += drill_signature(node.children[0], signature)
          end
          signature += '.' unless signature.empty?
          signature += node.children[1].to_s
        end
        signature
      end

      def returns_from node
        DeepInference.get_return_nodes(node)
      end

      module DeepInference
        class << self
          CONDITIONAL = [:if, :unless]
          REDUCEABLE = [:begin, :kwbegin]
          SKIPPABLE = [:def, :defs, :class, :sclass, :module]

          def get_return_nodes node
            return [] unless node.is_a?(Parser::AST::Node)
            result = []
            if REDUCEABLE.include?(node.type)
              result.concat get_return_nodes_from_children(node)
            elsif CONDITIONAL.include?(node.type)
              result.concat reduce_to_value_nodes(node.children[1..-1])
            else
              result.push node
            end
            result
          end

          private

          def get_return_nodes_from_children parent
            result = []
            nodes = parent.children.select{|n| n.is_a?(AST::Node)}
            nodes[0..-2].each do |node|
              next if SKIPPABLE.include?(node.type)
              if node.type == :return
                result.concat reduce_to_value_nodes([node.children[0]])
                # Return the result here because the rest of the code is
                # unreachable
                return result
              else
                result.concat get_return_nodes_only(node)
              end
            end
            result.concat reduce_to_value_nodes([nodes.last]) unless nodes.last.nil?
            result
          end

          def get_return_nodes_only parent
            result = []
            nodes = parent.children.select{|n| n.is_a?(AST::Node)}
            nodes.each do |node|
              next if SKIPPABLE.include?(node.type)
              if node.type == :return
                result.concat reduce_to_value_nodes([node.children[0]])
                # Return the result here because the rest of the code is
                # unreachable
                return result
              else
                result.concat get_return_nodes_only(node)
              end
            end
            result
          end

          def reduce_to_value_nodes nodes
            result = []
            nodes.each do |node|
              next unless node.is_a?(Parser::AST::Node)
              if REDUCEABLE.include?(node.type)
                result.concat get_return_nodes_from_children(node)
                # node.children.each do |child|
                #   result.concat reduce_to_value_nodes(child)
                # end
              elsif CONDITIONAL.include?(node.type)
                result.concat reduce_to_value_nodes(node.children[1..-1])
              elsif node.type == :return
                result.concat get_return_nodes(node.children[0])
              else
                result.push node
              end
            end
            result
          end
        end
      end
    end
  end
end
