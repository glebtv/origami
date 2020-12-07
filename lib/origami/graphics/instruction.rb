=begin

    This file is part of Origami, PDF manipulation framework for Ruby
    Copyright (C) 2016	Guillaume Delugré.

    Origami is free software: you can redistribute it and/or modify
    it under the terms of the GNU Lesser General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    Origami is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Lesser General Public License for more details.

    You should have received a copy of the GNU Lesser General Public License
    along with Origami.  If not, see <http://www.gnu.org/licenses/>.

=end

module Origami

   class InvalidPDFInstructionError < Error; end

   class PDF::Instruction
      using TypeConversion

      attr_reader :operator
      attr_accessor :operands
      attr_accessor :extra_data

      ALL_INSTRUCTION_OPERATORS = Hash[
         "b" => true, "B" => true, "B*" => true, "b*" => true, "BDC" => true, "BI" => true, "BMC" => true, "BT" => true, "BX" => true, "c" => true, "cm" => true, "CS" => true,
         "cs" => true, "d" => true, "d0" => true, "d1" => true, "Do" => true, "DP" => true, "EI" => true, "EMC" => true, "ET" => true, "EX" => true, "f" => true,
         "F" => true, "f*" => true, "G" => true, "g" => true, "gs" => true, "h" => true, "i" => true, "ID" => true, "j" => true, "J" => true, "K" => true, "k" => true,
         "l" => true, "m" => true, "M" => true, "MP" => true, "n" => true, "q" => true, "Q" => true, "re" => true, "RG" => true, "rg" => true, "ri" => true, "s" => true,
         "S" => true, "SC" => true, "sc" => true, "SCN" => true, "scn" => true, "sh" => true, "T*" => true, "Tc" => true, "Td" => true, "TD" => true, "Tf" => true,
         "Tj" => true, "TJ" => true, "TL" => true, "Tm" => true, "Tr" => true, "Ts" => true, "Tw" => true, "Tz" => true, "v" => true, "w" => true, "W" => true, "W*" => true,
         "y" => true, "'" => true, "\"" => true
      ].freeze

      @insns = Hash.new(operands: [], render: lambda{})

      def initialize(operator, *operands)
         @operator = operator
         @operands = operands.map!{|arg| arg.is_a?(Origami::Object) ? arg.value : arg}

         @extra_data = Hash[]

         if self.class.has_op?(operator)
            opdef = self.class.get_operands(operator)

            if not opdef.include?('*') and opdef.size != operands.size
               raise InvalidPDFInstructionError,
                      "Numbers of operands mismatch for #{operator}: #{operands.inspect}"
            end
         end
      end

      def render(canvas)
         self.class.get_render_proc(@operator)[canvas, *@operands]

         self
      end

      def solve_font font
         if font == :Helv
            BuiltInFont.new("Helvetica")
         elsif /^T\d+_\d+$/ =~ font.to_s
            BuiltInFont.new( "Arial" )
         else
            BuiltInFont.new( font.to_s )
         end
      end

      def to_s
         "#{operands.map{|op| op.to_o.to_s}.join(' ')}#{' ' unless operands.empty?}#{operator}\n"
      end

      def apply( page, canvas )
         #puts( "#{operator}: #{operands.to_s}" )
         #puts self.to_s

         case operator
         when 'cm' ## coordinate map ##
            page.graphics_manager.command_cm( *operands )
         when 'q' ## replicate and push graphic state ##
            page.graphics_manager.command_q
         when 'Q' ## pop graphic state
            page.graphics_manager.command_Q
         when 'Do' ## xobject
            xobj = page.Resources.XObject[ operands.first ] rescue nil
            xobj = xobj.solve if xobj.is_a?( ::Origami::Reference )
            if !xobj.nil?
               if xobj.Subtype.value != :Image
                  xcan = canvas.command_do( xobj, operands.first, xobj.no, xobj.generation )
                  if !xcan.nil?
                     page.graphics_manager.command_q
                     page.graphics_manager.current.set_context( xobj )
                     xobj.instructions.each{ |inst| inst.apply( page, xcan ) }
                     page.graphics_manager.command_Q
                  end
               end
            end
         when 're' ## rectangle stroke ##
            bl = page.graphics_manager.resolve( Point.new( operands[0], operands[1] ) )
            tr = page.graphics_manager.resolve( Point.new( operands[0] + operands[2], operands[1] + operands[3] ) )

            canvas.command_re( tr, bl )
         when 'BT' ## begin text ##
            page.graphics_manager.current.command_BT
            canvas.command_BT( page.graphics_manager.current )
         when 'ET' ## end text ##
            page.graphics_manager.current.command_ET
            canvas.command_ET
         when 'g' ## set nonstroking color, greyscale
            page.graphics_manager.current.command_g( *operands )
            canvas.command_g( *operands )
         when 'Td' ## move cursor to position x, y
            a_p = Point.new( operands[0], operands[1] )
            page.graphics_manager.current.command_Td( a_p )
            canvas.command_Td( a_p, page.graphics_manager.current )
         when 'TD' ## Move cursor to new line x, y
            a_p = Point.new( operands[0], operands[1] )
            page.graphics_manager.current.command_TD( a_p )
            canvas.command_Td( a_p, page.graphics_manager.current )
         when 'Tc' ## Character spacing x
            page.graphics_manager.current.command_Tc( operands.first )
         when 'Tw' ## Word spacing x
            page.graphics_manager.current.command_Tw( operands.first )
         when 'Tz' ## horizontal scaling spacing x
            page.graphics_manager.current.command_Tz( operands.first )
         when 'TL' ## Text leading x (distance between baselines in next line)
            page.graphics_manager.current.command_TL( operands.first )
         when 'Tr' ## text render mode
            page.graphics_manager.current.command_Tr( operands.first )
         when 'Ts' ## text rise
            page.graphics_manager.current.command_Ts( operands.first )
         when 'Tm'
            page.graphics_manager.current.command_Tm( *operands )
            canvas.command_Tm( page.graphics_manager.current.text_matrix, page.graphics_manager.current )
         when 'T*'
            page.graphics_manager.current.command_T_star()
            canvas.command_T_star( page.graphics_manager.current.text_leading, page.graphics_manager.current )
         when 'Tf' ## set font and font size
            font = nil

            if !page.graphics_manager.current.context.nil?
               a_ctx = page.graphics_manager.current.context
               if a_ctx.Resources && a_ctx.Resources.Font
                  font = a_ctx.Resources.Font[ operands.first ]
                  if font.is_a?( Reference )
                     font = font.solve
                  end
               end
            end

            if font.nil? && !page.Resources.Font.nil?

               font = page.Resources.Font[ operands.first ]
               if font.is_a?( Reference )
                  font = font.solve
               end
            end

            if font.nil?
               if page.Parent && page.Parent.Kids
                  a_page = page.Parent.Kids.detect {|p| a_p = p.is_a?( Origami::Reference ) ? p.solve : p; a_p.Resources && a_p.Resources.Font && a_p.Resources.Font[ operands.first ]}
                  if !a_page.nil?
                     a_page = a_page.solve if a_page.is_a?( Reference )
                     font = a_page.Resources.Font[ operands.first ]
                     if font.is_a?( Reference )
                        font = font.solve
                     end
                  end
               end
            end

            if font.nil?
               font = solve_font( operands.first )
            end

            if !font.nil?
               page.graphics_manager.current.command_Tf( font, operands[1] )
               canvas.command_Tf( font, page.graphics_manager.current )
            else
               raise "Font not found"
            end
         when '"'
            page.graphics_manager.current.command_T_star()
            canvas.command_T_star( page.graphics_manager.current.text_leading, page.graphics_manager.current )
            page.graphics_manager.current.command_Tw( operands[0] )
            page.graphics_manager.current.command_Tc( operands[0] )
            str = page.graphics_manager.current.text_font.decode_text( operands[2] )
            canvas.command_Tj( str, page.graphics_manager.current )
         when '\''
            page.graphics_manager.current.command_T_star( )
            canvas.command_T_star( page.graphics_manager.current.text_leading, page.graphics_manager.current)

            str = page.graphics_manager.current.text_font.decode_text( operands[0] )
            canvas.command_Tj( str, page.graphics_manager.current )
         when 'Tj' ## print text
            str = page.graphics_manager.current.text_font.decode_text( operands[0] )
            canvas.command_Tj( str, page.graphics_manager.current )
         when 'TJ'
            ops = operands.first
            ops.each do |op|
               if !op.is_a?( ::String )
                  canvas.command_TJ( nil, op, page.graphics_manager.current )
               else
                  str = page.graphics_manager.current.text_font.decode_text( op )
                  canvas.command_TJ( str, nil, page.graphics_manager.current )
               end
            end
         end

      end

        class << self
            def insn(operator, *operands, &render_proc)
                @insns[operator] = {}
                @insns[operator][:operands] = operands
                @insns[operator][:render] = render_proc || lambda{}
            end

            def has_op?(operator)
                @insns.has_key? operator
            end

            def get_render_proc(operator)
                @insns[operator][:render]
            end

            def get_operands(operator)
                @insns[operator][:operands]
            end

            def sanitize_operator( operator )
               ops = []
               remaining = operator
               while remaining.length > 0
                  len = remaining.length
                  found = false
                  cutoff = 0
                  while !found && cutoff < len
                     check = remaining[0...(len-cutoff)]
                     if ALL_INSTRUCTION_OPERATORS[ check ]
                        ops << check
                        found = true
                     else
                        cutoff += 1
                     end
                  end

                  if found
                     remaining = remaining[(len-cutoff)..len-1]
                  else
                     raise InvalidPDFInstructionError, "Operator: #{operator}"
                  end
               end

               ops
            end

            def parse(stream)
                operands = []
                while type = Object.typeof(stream, true)
                    operands.push type.parse(stream)
                end

                if not stream.eos?
                    if stream.scan(/(?<operator>[[:graph:]&&[^\[\]<>()%\/]]+)/).nil?
                        raise InvalidPDFInstructionError, "Operator: #{(stream.peek(10) + '...').inspect}"
                    end

                    operator = stream['operator']
                    operators = self.sanitize_operator( operator )
                    insts = [ PDF::Instruction.new(operators.first, *operands) ]
                    operators[1..-1].each {|op| insts << PDF::Instruction.new( op ) }
                    lastinst = insts.last


                    if lastinst.operator == "BI"

                       rgx = Regexp.new( WHITESPACES + "ID" )
                       h = Hash[]
                       image_data = nil
                       while (!stream.scan( rgx ) )
                          k = Name.parse( stream )
                          t = Object.typeof( stream )
                          v = t.parse( stream )

                          h[k] = v
                       end
                       image_data = stream.scan_until(/EI/)
                       image_data = image_data[0...-2].strip
                       lastinst.extra_data[:image_data] = image_data
                       lastinst.extra_data[:attributes] = h

                    end
                    insts
                else
                    unless operands.empty?
                        raise InvalidPDFInstructionError, "No operator given for operands: #{operands.map(&:to_s).join(' ')}"
                    end
                end
            end
        end

    end
end
