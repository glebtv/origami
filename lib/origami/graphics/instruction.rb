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

      @insns = Hash.new(operands: [], render: lambda{})

      def initialize(operator, *operands)
         @operator = operator
         @operands = operands.map!{|arg| arg.is_a?(Origami::Object) ? arg.value : arg}

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
         else
            BuiltInFont.new( font.to_s )
         end
      end

      def to_s
         "#{operands.map{|op| op.to_o.to_s}.join(' ')}#{' ' unless operands.empty?}#{operator}\n"
      end

      def apply( page, canvas )
         #APPLOG.warn( "#{operator}: #{operands.to_s}" )
         case operator
         when 'cm' ## coordinate map ##
            page.graphics_manager.command_cm( *operands )
         when 'q' ## replicate and push graphic state ##
            page.graphics_manager.command_q
         when 'Q' ## pop graphic state
            page.graphics_manager.command_Q
         when 'Do' ## xobject
            xobj = page.Resources.xobjects[ operands.first ]
            if !xobj.nil?
               xcan = canvas.command_do( operands.first, xobj.no, xobj.generation )
               xobj.instructions.each{ |inst| inst.apply( page, xcan ) }
            end
         when 're' ## rectangle stroke ##
            bl = page.graphics_manager.resolve( Point.new( operands[0], operands[1] ) )
            tr = page.graphics_manager.resolve( Point.new( operands[0] + operands[2], operands[1] + operands[3] ) )

            canvas.command_re( tr, bl )
         when 'BT' ## begin text ##
            page.graphics_manager.current.command_BT
            canvas.command_BT
         when 'ET' ## end text ##
            page.graphics_manager.current.command_ET
            canvas.command_ET
         when 'g' ## set nonstroking color, greyscale
            page.graphics_manager.current.command_g( *operands )
            canvas.command_g( *operands )
         when 'Td' ## move cursor to position x, y
            a_p = Point.new( operands[0], operands[1] )
            page.graphics_manager.current.command_Td( a_p )
            canvas.command_Td( a_p )
         when 'TD' ## Move cursor to new line x, y
            a_p = Point.new( operands[0], operands[1] )
            page.graphics_manager.current.command_TD( a_p )
            canvas.command_Td( a_p )
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
            canvas.command_Tm( page.graphics_manager.current.text_matrix )
         when 'T*'
            page.graphics_manager.current.command_T_star()
            canvas.command_T_star
         when 'Tf' ## set font and font size
            #APPLOG.warn( "Loading font: #{operands.first}")
            font = page.Resources.Font[ operands.first ]
            if font.is_a?( Reference )
               font = font.solve
            end

            if font.nil?
               font = solve_font( operands.first )
            end

            if !font.nil?
               page.graphics_manager.current.command_Tf( font, operands[1] )
            else
               raise "Font not found"
            end
         when '"'
            page.graphics_manager.current.command_T_star()
            canvas.command_T_star
            page.graphics_manager.current.command_Tw( operands[0] )
            page.graphics_manager.current.command_Tc( operands[0] )
            str = page.graphics_manager.current.text_font.decode_text( operands[2] )
            #APPLOG.warn( "    '#{str}'")
            canvas.command_Tj( str, page.graphics_manager.current )
         when '\''
            page.graphics_manager.current.command_T_star( )
            canvas.command_T_star

            str = page.graphics_manager.current.text_font.decode_text( operands[0] )
            #APPLOG.warn( "    '#{str}'")
            canvas.command_Tj( str, page.graphics_manager.current )
         when 'Tj' ## print text
            str = page.graphics_manager.current.text_font.decode_text( operands[0] )
            #APPLOG.warn( "    '#{str}'")
            canvas.command_Tj( str, page.graphics_manager.current )
         when 'TJ'
            ops = operands.first
            last = ops[ -1 ]
            pre = ops[0...-1]
            pre.each_slice( 2 ).each do |slice|
               str = page.graphics_manager.current.text_font.decode_text( slice[0] )
               #APPLOG.warn( "    '#{str}'")
               amt = slice[ 1]
               canvas.command_TJ( str, amt, page.graphics_manager.current )
            end

            str = page.graphics_manager.current.text_font.decode_text( last )
            #APPLOG.warn( "    '#{str}'")
            canvas.command_TJ( str, nil, page.graphics_manager.current )
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
                    PDF::Instruction.new(operator, *operands)
                else
                    unless operands.empty?
                        raise InvalidPDFInstructionError, "No operator given for operands: #{operands.map(&:to_s).join(' ')}"
                    end
                end
            end
        end

    end
end
