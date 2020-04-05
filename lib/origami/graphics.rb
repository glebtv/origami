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
         "[ x: #{x}, y: #{y} ]"
      end
  end

  class TransformMatrix
      def initialize a, b, c, d, e, f
         @mat = [ a,b,c,d,e,f ]
      end

      def transform point
         p = Point.new( point.x * @mat[0] + point.y * @mat[2] + 1.0 * @mat[4], point.x * @mat[1] + point.y * @mat[3] + 1.0 * @mat[5] )
         p
      end

      def clone
         TransformMatrix.new( *@mat )
      end
  end

    class GraphicsManager
      def initialize
         @gss = []
         @gss.push( GraphicsState.new )
      end

      def command_g
         cur = @gss.last
         @gss.push( GraphicsState.new )
         @gss.last.replicate( cur )
      end

      def command_G
         @gss.pop
      end

      def command_cm *args
         @gss.last.command_cm *args
      end

      def resolve point
         @gss.last.resolve( point )
      end
   end

   class GraphicsState

      def initialize
         @coordinate_transform = []
      end

      attr_reader :coordinate_transform

      def replicate( state )
         @coordinate_transform = state.coordinate_transform.map{ |ct| ct.clone }
      end

      def command_cm *args
         @coordinate_transform.clear
         @coordinate_transform.push( TransformMatrix.new( *args ) )
      end

      def resolve point
         @coordinate_transform.reduce( point ) { |memo, ct| ct.transform( memo ) }
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
