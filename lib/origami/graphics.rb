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

    module Graphics
        #
        # Common graphics Exception class for errors.
        #
        class Error < Origami::Error; end
    end

    class Point
      def initialize( x, y )
         @x = x
         @y = y
      end

      attr_accessor :x, :y

      def clone
         Point.new( x, y )
      end

      def to_s
         inspect
      end

      def inspect
         "[ x: #{x}, y: #{y} ]"
      end

      def *(other)
         if other.is_a?( Integer )
            Point.new( x * other, y * other )
         elsif other.is_a?( TransformMatrix )
            other.transform self
         else
            Raise "Invalid point multiplier"
         end
      end

      def cell r, c
         return 0 if c > 2
         return 0 if r > 0
         if c == 0
            @x
         elsif c == 1
            @y
         else
            1
         end
      end
  end

  class TransformMatrix
      def initialize a, b, c, d, e, f
         @mat = [ a,b,c,d,e,f ]
      end

      def transform point, opts = Hash[]
         tran_amt = opts[:no_translate] ? 0.0 : 1.0
         p = Point.new( point.x * @mat[0] + point.y * @mat[2] + tran_amt * @mat[4], point.x * @mat[1] + point.y * @mat[3] + tran_amt * @mat[5] )
         p
      end

      def inspect
         @mat.to_s
      end

      def to_s
         inspect
      end

      def clone
         TransformMatrix.new( *@mat )
      end

      def cell r,c
         return 0 if c > 2
         return 0 if r > 2
         if c == 2
            r==2 ? 1 : 0
         else
            @mat[ r*2 + c ]
         end
      end

      def cell! r,c,val
         return nil if c > 1
         return nil if r > 2
         @mat[ r*2 + c ] = val
      end

      def *(other)
         if other.is_a?( ::Integer )
            newtr = @mat.map{|el| el* other }
            TransformMatrix.new( *newtr )
         elsif other.is_a?( TransformMatrix )
            newtr = (0..5).map do |idx|
               r = idx / 2
               c = idx % 2
               (0..2).reduce(0) do |memo,pos|
                  memo + ( self.cell( r, pos ) * other.cell( pos, c ) )
               end
            end
            TransformMatrix.new( *newtr )
         else
            raise "Invalid transform matrix multiplier"
         end
      end
  end

    class GraphicsManager
      def initialize
         @gss = []
         @gss.push( GraphicsState.new )
      end

      def command_q
         cur = @gss.last
         @gss.push( GraphicsState.new )
         @gss.last.replicate( cur )
      end

      def command_Q
         @gss.pop
      end

      def command_cm *args
         @gss.last.command_cm *args
      end

      def resolve point
         @gss.last.resolve( point )
      end

      def current
         @gss.last
      end
   end

   class GraphicsState

      def initialize
         @coordinate_transform = TransformMatrix.new( 1, 0, 0, 1, 0, 0 )

         @text_character_spacing = 0.0
         @text_word_spacing = 0.0
         @text_horizontal_scaling = 100
         @text_leading = 0.0
         @text_font = nil
         @text_font_size = nil
         @text_rendering_mode = 0
         @text_rise = 0.0
         @text_knockout = 0.0
         @text_matrix = nil
         @text_line_matrix = nil
         @context = nil
      end

      attr_reader :coordinate_transform

      attr_reader :text_character_spacing, :text_word_spacing, :text_horizontal_scaling, :text_leading, :text_font, :text_font_size, :text_rendering_mode, :text_rise, :text_knockout, :text_matrix, :text_line_matrix, :context

      def replicate( state )
         @coordinate_transform = state.coordinate_transform.clone
         @context = state.context

         self.replicate_text_state( state )

         self
      end

      def set_context a_context
         @context = a_context
         if @context.Matrix
            self.command_cm( *context.Matrix.to_a )
         end
      end

      def replicate_text_state state
         @text_character_spacing = state.text_character_spacing
         @text_word_spacing = state.text_word_spacing
         @text_horizontal_scaling = state.text_horizontal_scaling
         @text_leading = state.text_leading
         @text_font = state.text_font
         @text_font_size = state.text_font_size
         @text_rendering_mode = state.text_rendering_mode
         @text_rise = state.text_rise
         @text_knockout = state.text_knockout
         @text_matrix = state.text_matrix.clone
         @text_line_matrix = state.text_line_matrix.clone
         @text_prerender_matrix = nil
      end

      def text_origin
         temp_matrix = self.text_prerender_matrix
         Point.new( temp_matrix.cell(2,0), temp_matrix.cell(2,1) )
      end

      def text_prerender_matrix
         return @text_prerender_matrix unless @text_prerender_matrix.nil?
         @text_prerender_matrix = self.text_matrix * self.coordinate_transform
      end

      def glyph_bbox char
         per_em = @text_font.units_per_em.to_f
         bbox = @text_font.glyph_bbox( char )

         return text_font_bbox if bbox.nil?

         x1 = bbox[0].to_f * @text_font_size.to_f / per_em
         y1 = bbox[1].to_f * @text_font_size.to_f / per_em

         x2 = bbox[2].to_f * @text_font_size.to_f / per_em
         y2 = bbox[3].to_f * @text_font_size.to_f / per_em

         bl = Point.new( x1, y1 )
         tr = Point.new( x2, y2 )
         [ bl, tr ]
      end

      def glyph_kerning char1, char2
            per_em = @text_font.units_per_em.to_f
            aw = @text_font.glyph_kerning( char1, char2 )

            return 0 if aw.nil?
            aw * @text_font_size.to_f / per_em
      end

      def glyph_advance char
         per_em = @text_font.units_per_em.to_f
         aw = @text_font.glyph_advance( char )

         return @text_font_size.to_f / 2.0 if aw.nil?

         wid = aw * @text_font_size.to_f / per_em

         wid
      end

      def text_font_bbox
         bbox = @text_font.bbox
         per_em = @text_font.units_per_em.to_f

         x1 = bbox[0].to_f * @text_font_size.to_f / per_em
         y1 = bbox[1].to_f * @text_font_size.to_f / per_em

         x2 = bbox[2].to_f * @text_font_size.to_f / per_em
         y2 = bbox[3].to_f * @text_font_size.to_f / per_em

         bl = Point.new( x1, y1 )
         tr = Point.new( x2, y2 )
         [ bl, tr ]
      end

      def text_displace_x amount, word_flag = false
         new_amount = ( amount + @text_character_spacing + ( word_flag ? @text_word_spacing : 0 ) ) * @text_horizontal_scaling / 100.0
         a_p = self.text_matrix.transform( Point.new( new_amount, 0 ), :no_translate => true )

         @text_matrix.cell!( 2, 0, @text_matrix.cell( 2, 0 ) + a_p.x )
         @text_matrix.cell!( 2, 1, @text_matrix.cell( 2, 1 ) + a_p.y )
         @text_prerender_matrix = nil
      end

      def command_BT
         @text_prerender_matrix = nil
         @text_matrix = TransformMatrix.new( 1,0,0,1,0,0 )
         @text_line_matrix = TransformMatrix.new( 1,0,0,1,0,0 )
      end

      def command_g grscale
         grscale
      end

      def command_ET
         @text_prerender_matrix = nil
         @text_matrix = nil
         @text_line_matrix = nil
      end

      def command_Tc charspace
         @text_character_spacing = charspace
      end

      def command_Tw wordspace
         @text_word_spacing = wordspace
      end

      def command_Tz scale
         @text_horizontal_scaling = scale
      end

      def command_Ts rise
         @text_rise = rise
      end

      def command_Tr render
         @text_rendering_mode = render
      end

      def command_TL leading
         @text_leading = leading
      end

      def command_TD point
         command_TL point.y * -1
         command_Td point
      end

      def command_Td point
         @text_prerender_matrix = nil
         a_matr = TransformMatrix.new( 1,0,0,1,point.x, point.y )
         @text_line_matrix = a_matr * @text_line_matrix
         @text_matrix = @text_line_matrix.clone
      end

      def post_command_TJ amount

      end

      def command_Tm *args
         @text_prerender_matrix = nil
         @text_matrix = TransformMatrix.new( *args )
         @text_line_matrix = TransformMatrix.new( *args )
      end

      def command_T_star
         a_p = Point.new( 0, -1 * @text_leading )
         command_Td a_p
      end

      def command_Tf font, point_size
         @text_font = font
         @text_font_size = point_size
      end

      def command_cm *args
         @text_prerender_matrix = nil
         @coordinate_transform = TransformMatrix.new( *args ) * @coordinate_transform
      end

      def resolve point
         @coordinate_transform.transform( point )
      end
   end
end

require 'origami/graphics/instruction'
require 'origami/graphics/state'
require 'origami/graphics/colors'
require 'origami/graphics/path'
require 'origami/graphics/xobject'
require 'origami/graphics/text'
require 'origami/graphics/patterns'
require 'origami/graphics/render'
