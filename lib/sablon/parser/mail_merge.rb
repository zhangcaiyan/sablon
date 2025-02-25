module Sablon
  module Parser
    class MailMerge
      class MergeField
        attr_accessor :block_reference_count
        KEY_PATTERN = /^\s*MERGEFIELD\s+([^ ]+)\s+\\\*\s+MERGEFORMAT\s*$/

        def initialize
          @block_reference_count = 0
        end

        def valid?
          expression
        end

        def expression
          $1 if @raw_expression =~ KEY_PATTERN
        end

        private

        # removes all nodes associated with the merge field if the reference
        # count is less than or equal to 1
        def remove_or_decrement_ref(*nodes)
          if @block_reference_count > 1
            @block_reference_count -= 1
          else
            nodes.each(&:remove)
          end
        end

        def replace_field_display(node, content, env)
          paragraph = node.ancestors(".//w:p").first
          display_node = get_display_node(node)
          content.append_to(paragraph, display_node, env)
          display_node.remove
        end

        def get_display_node(node)
          node.search(".//w:t").first
        end
      end

      class ComplexField < MergeField
        def initialize(nodes)
          super()
          @nodes = nodes
          @raw_expression = @nodes.flat_map {|n| n.search(".//w:instrText").map(&:content) }.join
        end

        def valid?
          separate_node && get_display_node(pattern_node) && expression
        end

        def replace(content, env)
          replace_field_display(pattern_node, content, env)
          (@nodes - [pattern_node]).each(&:remove)
        end

        # removes only the merge field in question
        def remove
          remove_or_decrement_ref(*@nodes)
        end

        def remove_parent(selector)
          node = @nodes.first
          remove_or_decrement_ref(node.ancestors(selector).first)
        end

        def ancestors(*args)
          @nodes.first.ancestors(*args)
        end

        def start_node
          @nodes.first
        end

        def end_node
          @nodes.last
        end

        private

        def pattern_node
          separate_node.next_element
        end

        def separate_node
          @nodes.detect {|n| !n.search(".//w:fldChar[@w:fldCharType='separate']").empty? }
        end
      end

      class SimpleField < MergeField
        def initialize(node)
          super()
          @node = node
          @raw_expression = @node["w:instr"]
        end

        def replace(content, env)
          remove_extra_runs!
          replace_field_display(@node, content, env)
          @node.replace(@node.children)
        end

        # removes only the merge field in question
        def remove
          remove_or_decrement_ref(@node)
        end

        # removes the parent node containing the merge field
        def remove_parent(selector)
          remove_or_decrement_ref(@node.ancestors(selector).first)
        end

        def ancestors(*args)
          @node.ancestors(*args)
        end

        def start_node
          @node
        end
        alias_method :end_node, :start_node

        private

        def remove_extra_runs!
          @node.search(".//w:r")[1..-1].each(&:remove)
        end
      end

      def parse_fields(xml)
        fields = []
        xml.traverse do |node|
          if node.name == "fldSimple"
            field = SimpleField.new(node)
          elsif node.name == "fldChar" && node["w:fldCharType"] == "begin"
            field = build_complex_field(node)
          end
          fields << field if field && field.valid?
        end
        fields
      end

      private

      def build_complex_field(node)
        return if node.nil?

        possible_field_node = node.parent
        field_nodes = [possible_field_node]
        while possible_field_node && possible_field_node.search(".//w:fldChar[@w:fldCharType='end']").empty?
          possible_field_node = possible_field_node.next_element
          field_nodes << possible_field_node
        end
        # skip instantiation if no end tag
        ComplexField.new(field_nodes) if field_nodes.last
      end
    end
  end
end
