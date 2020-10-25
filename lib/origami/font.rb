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

    #
    # Embedded font stream.
    #
    class FontStream < Stream
        field   :Subtype,                 :Type => Name
        field   :Length1,                 :Type => Integer
        field   :Length2,                 :Type => Integer
        field   :Length3,                 :Type => Integer
        field   :Metadata,                :Type => MetadataStream
    end

    #
    # Class representing a font details in a document.
    #
    class FontDescriptor < Dictionary
        include StandardObject

        FIXEDPITCH  = 1 << 1
        SERIF       = 1 << 2
        SYMBOLIC    = 1 << 3
        SCRIPT      = 1 << 4
        NONSYMBOLIC = 1 << 6
        ITALIC      = 1 << 7
        ALLCAP      = 1 << 17
        SMALLCAP    = 1 << 18
        FORCEBOLD   = 1 << 19

        field   :Type,                    :Type => Name, :Default => :FontDescriptor, :Required => true
        field   :FontName,                :Type => Name, :Required => true
        field   :FontFamily,              :Type => String, :Version => "1.5"
        field   :FontStretch,             :Type => Name, :Default => :Normal, :Version => "1.5"
        field   :FontWeight,              :Type => Integer, :Default => 400, :Version => "1.5"
        field   :Flags,                   :Type => Integer, :Required => true
        field   :FontBBox,                :Type => Rectangle
        field   :ItalicAngle,             :Type => Number, :Required => true
        field   :Ascent,                  :Type => Number
        field   :Descent,                 :Type => Number
        field   :Leading,                 :Type => Number, :Default => 0
        field   :CapHeight,               :Type => Number
        field   :XHeight,                 :Type => Number, :Default => 0
        field   :StemV,                   :Type => Number
        field   :StemH,                   :Type => Number, :Default => 0
        field   :AvgWidth,                :Type => Number, :Default => 0
        field   :MaxWidth,                :Type => Number, :Default => 0
        field   :MissingWidth,            :Type => Number, :Default => 0
        field   :FontFile,                :Type => FontStream
        field   :FontFile2,               :Type => FontStream, :Version => "1.1"
        field   :FontFile3,               :Type => FontStream, :Version => "1.2"
        field   :CharSet,                 :Type => String, :Version => "1.1"
    end

    #
    # Class representing a character encoding in a document.
    #
    class Encoding < Dictionary
        include StandardObject

        field   :Type,                    :Type => Name, :Default => :Encoding
        field   :BaseEncoding,            :Type => Name
        field   :Differences,             :Type => Array
    end

    module FontStuff
      def decode_text text
         text.unpack('C*').pack('U*')
      end

      def bbox
         font_file.bbox
      end

      def get_font_name
         fn = self.get_base_font_name

         return nil if fn.nil? || fn.length == 0

         parts = fn.split("+")
         parts = parts.last
         parts = parts.split("-")
         a_name = parts.first

         if a_name[0] == "*"
           a_name[0] = ""
         end

         a_name
      end

      def get_font_style
         fn = self.get_base_font_name

         parts = fn.split("+")
         parts = parts.last
         parts = parts.split("-")
         style = (parts[1] || "regular").downcase

         if !( style == "bold" || style == "regular" || style == "italics" )
           style = "regular"
         end

         style
      end

      def local_font_file
         if !self.FontDescriptor.nil?
            if self.FontDescriptor.FontFile1
               self.FontDescriptor.FontFile1
            elsif self.FontDescriptor.FontFile2
               self.FontDescriptor.FontFile2
            elsif self.FontDescriptor.FontFile3
               self.FontDescriptor.FontFile3
            end
         end
      end

      def parse_font_file!
         lff = self.local_font_file
         raise "Could not identify font" if lff.nil?

         @my_font_file = TTFunk::File.open( StringIO.new( lff.data ) )
      end

      def load_font!
         return if @_font_file_loaded
         @_font_file_loaded = true

         a_name = get_font_name
         if a_name.nil?
            parse_font_file!
            return true
         end
         style = get_font_style

         fn = self.get_base_font_name

         if a_name.downcase == "symbol"
            a_name = "Symbola"
         elsif a_name.downcase == "palatino linotype" || a_name.downcase == "palatinolinotype"
            a_name = "FreeSerif"
         elsif a_name.downcase == "times"
           a_name = "Liberation Serif"
           style = "regular"
         end

         r = `fc-match -s "#{a_name}"`
         #APPLOG.warn( a_name )

         list = r.force_encoding("UTF-8").split("\n")
         rgx = /(.*): "(.*)" "(.*)"/
         a_thing = list.map do |a_r|
            match = rgx.match( a_r )
            if !match.nil?
               [match[1],match[2]]
            end
         end.select do |a_r|
            if !a_r.nil?
               a_r[0][-4..-1] == ".ttf"
            end
         end.first

         raise "Cannot find font file for #{fn}" if a_thing.nil?

         fname = a_thing[1]

         r = `fc-list "#{fname}"`

         #APPLOG.warn( fname )

         fonts = r.force_encoding("UTF-8").split("\n")

         rgx2 = /(.*): (.*):style=(\w+)/
         fonts = fonts.map do |a_font|
           m2 = rgx2.match( a_font )
           if !m2.nil?
             ah = Hash[
                 :file => m2[1],
                 :font => m2[2],
                 :style => m2[3].split(",")
             ]
             new_styles = Hash[]
             ah[:style].each do |st|
                 st = st.downcase
                 if st == "normal" || st == "regular" || st == "plain" || st == "book"
                    new_styles[ "normal" ] = true
                    new_styles[ "regular" ] = true
                    new_styles[ "plain" ] = true
                    new_styles[ "book" ] = true
                 else
                    new_styles[ st ] = true
                 end
             end

             ah[:style ] = new_styles

             ah
           end
         end.compact

         raise "Cannot find a font file for #{fn}" if fonts.length == 0

         a_font = fonts.detect{|f| f[:style][ style.downcase ] }


         raise "Cannot find the font file for #{fn}" if a_font.nil?

         a_file_name = a_font[:file]

         if a_file_name[-4..-1] != ".ttf"
            raise "Unsupported font file format #{a_file_name} for font #{fn}"
         end
         #APPLOG.warn( a_font[:file] )
         @my_font_file = TTFunk::File.open( a_font[:file] )

         raise "Could not open font file for #{fn}" if @my_font_file.nil?
         true
      end

      def font_file
         load_font!
         @my_font_file
      end

      def units_per_em
         font_file.header.units_per_em
      end

      def get_gid char
         code = char.unpack1('U*')
         gid = font_file.cmap.unicode.first[ code ]
      end

      def glyph_kerning char1, char2
         k = [ get_gid( char1 ), get_gid( char2 ) ]
         return 0 if font_file.kerning.nil? || font_file.kerning.tables.nil? || font_file.kerning.tables.first.nil? || font_file.kerning.tables.first.pairs.nil?
         font_file.kerning.tables.first.pairs[ k ]
      end

      def glyph_advance character
         gid = get_gid character
         hm = font_file.horizontal_metrics.for( gid )
         hm.nil? ? nil : hm.advance_width
      end

      def glyph_bbox character
         if character == " "
            [ 0, 0, units_per_em, glyph_advance( character ) ]
         else
            gid = get_gid character

            glyph = font_file.glyph_outlines.for( gid )
            #APPLOG.warn( "Lookup glpyh: #{character},#{code},#{gid},#{glyph.nil?}")
            APPLOG.warn( "Unable to find glyph for character #{character} in #{self.get_base_font_name}") if glyph.nil?
            glyph.nil? ? nil : [ glyph.x_min, glyph.y_min, glyph.x_max, glyph.y_max ]
         end
      end

       class ByteRange
          def initialize low, high
             @low = low
             @high = high
          end

          def contains byte_str
             v = byte_str.is_a?( ByteString ) ? byte_str.value : byte_str
             @low.value <= v && v <= @high.value
          end

          def byte_size_range
             @low.bytesize
          end
       end

       class ByteString
          def initialize( str )
             if str[0] == "<" && str[-1] == ">"
                str = str[1..-2]
             end
             @raw_str = str
             @bytesize = str.length / 2
             @packed = [ @raw_str ].pack('H*')
          end

          def bytesize
             @bytesize
          end

          def value
             @packed
          end
       end
    end

    class BuiltInFont
      include FontStuff

      def initialize( name )
         @name = name
      end

      def get_base_font_name
         @name
      end

      def Encoding
         "Gobbldeegook"
      end
    end

    #
    # Class representing a rendering font in a document.
    #
    class Font < Dictionary
        include StandardObject
        include FontStuff

        field   :Type,                    :Type => Name, :Default => :Font, :Required => true
        field   :Subtype,                 :Type => Name, :Required => true
        field   :Name,                    :Type => Name
        field   :FirstChar,               :Type => Integer
        field   :LastChar,                :Type => Integer
        field   :Widths,                  :Type => Array.of(Number)
        field   :FontDescriptor,          :Type => FontDescriptor
        field   :Encoding,                :Type => [ Name, Encoding ], :Default => :MacRomanEncoding
        field   :ToUnicode,               :Type => Stream

        def get_base_font_name
           if self.FontDescriptor && self.FontDescriptor.FontName
             fn = self.FontDescriptor.FontName.value.to_s
          elsif self.BaseFont
             self.BaseFont.value.to_s
          else
             raise "Unable to determine font name"
          end
        end

        def font_file
           load_font!
           @my_font_file
        end

        def units_per_em
           font_file.header.units_per_em || 1000

        end

        def get_gid char
           code = char.unpack1('U*')
           gid = font_file.cmap.unicode.first[ code ]
        end

        def glyph_kerning char1, char2
           k = [ get_gid( char1 ), get_gid( char2 ) ]
           return 0 if font_file.kerning.nil? || font_file.kerning.tables.nil? || font_file.kerning.tables.first.nil? || font_file.kerning.tables.first.pairs.nil?
           font_file.kerning.tables.first.pairs[ k ]
        end

        def glyph_advance character
           code = character.unpack1('U*')
           gid = font_file.cmap.unicode.first[ code ]
           hm = font_file.horizontal_metrics.for( gid )
           hm.nil? ? nil : hm.advance_width
        end

        def glyph_bbox character
           if character == " "
              [ 0, 0, units_per_em, glyph_advance( character ) ]
           else
              code = character.unpack1('U*')
              gid = font_file.cmap.unicode.first[ code ]
              glyph = font_file.glyph_outlines.for( gid )
              APPLOG.warn( "Unable to find glyph for character #{character} in #{self.FontDescriptor.FontName.value.to_s}") if glyph.nil?
              glyph.nil? ? nil : [ glyph.x_min, glyph.y_min, glyph.x_max, glyph.y_max ]
           end
        end

         class ByteRange
            def initialize low, high
               @low = low
               @high = high
            end

            def contains byte_str
               v = byte_str.is_a?( ByteString ) ? byte_str.value : byte_str
               @low.value <= v && v <= @high.value
            end

            def byte_size_range
               @low.bytesize
            end

            def to_s
               "Range: #{@low} -> #{@high}"
            end

            def inspect
               to_s
            end

         end

         class ByteString

            def self.from_int an_int
               th = an_int.to_s( 16 )
               a_str = "<" + "0000"[0...(4-th.length) ] + th + ">"
               self.new( a_str )
            end

            def initialize( str )
               if str[0] == "<" && str[-1] == ">"
                  str = str[1..-2]
               end
               @raw_str = str
               @bytesize = str.length / 2
               @packed = [ @raw_str ].pack('H*')
            end

            def raw_str
               @raw_str
            end

            def to_s
               @raw_str
            end

            def inspect
               to_s
            end

            def to_i
               @raw_str.to_i( 16 )
            end

            def bytesize
               @bytesize
            end

            def value
               @packed
            end
         end

         class CMap

            def initialize cmap, font
               @cmap = cmap
               @font = font

               @cidmap = Hash[]

               @is_identity = false
               @descendant = font.DescendantFonts.first

               @ranges = Hash[]
               @max_range_length = 0
               @uniform_range = false

               if !font.Encoding.nil? && font.Encoding.value == :"Identity-H"
                  @is_identity = true
               elsif !@descendant.nil? && !@descendant.CIDSystemInfo.nil? && @descendant.CIDSystemInfo.Ordering == "identity"
                  @is_identity = true
               end

               if !@is_identity
                  Raise "Unknown CMAP"
               end

               pscode = []
               if cmap.nil? || cmap.data.nil?
                  @uniform_range = true
                  @max_range_length = 2

                  return
               end

               pscode = cmap.data.split(/\r?\n/)

               in_bfchar = false
               in_bfrange = false
               in_codespace = false

               while pscode.length > 0
                  cur = pscode.shift
                  toks = cur.split(/ +/)

                  if toks.last == "endcodespacerange"
                     in_codespace = false
                  elsif in_codespace
                     if toks.length != 2
                        toks = cur.scan( /<[0-9A-Fa-f]+>/ )
                     end
                     low = ByteString.new( toks.first )
                     high = ByteString.new( toks.last )
                     range = ByteRange.new( low, high )
                     if @ranges[ range.byte_size_range ].nil?
                        @ranges[ range.byte_size_range ] = []
                        @max_range_length = range.byte_size_range if @max_range_length < range.byte_size_range
                     end
                     @ranges[ range.byte_size_range ] << range
                  elsif toks.last == "begincodespacerange"
                     in_codespace = true
                  end

                  if toks.last == "endbfrange"
                     in_bfrange = false
                  elsif in_bfrange
                     toks = cur.scan( /<[0-9A-Fa-f]+>/ )
                     a_start = ByteString.new( toks.first )
                     a_end = ByteString.new( toks[1] )
                     a_base = ByteString.new( toks.last )

                     (a_start.to_i..a_end.to_i).each do |i|
                        inc = i - a_start.to_i
                        cur = ByteString.from_int( i )
                        newb = ByteString.from_int( a_base.to_i + inc )
                        @cidmap[ cur.value ] = newb
                     end

                  elsif toks.last == "beginbfrange"
                     in_bfrange = true
                  end

                  if toks.last == "endbfchar"
                     in_bfchar = false
                  elsif in_bfchar
                     toks = cur.scan( /<[0-9A-Fa-f]+>/ )
                     a_k = ByteString.new( toks.first )
                     a_v = ByteString.new( toks.last )
                     @cidmap[ a_k.value ] = a_v
                  elsif toks.last == "beginbfchar"
                     in_bfchar = true
                  end
               end

               if @ranges.keys.length == 1
                  @uniform_range = true
               end
            end

            def my_cidmap
               @cidmap
            end

            def decode str
               output = ""

               idx = 0
               old_idx = nil
               cur = ""
               while idx < str.length && idx != old_idx

                  old_idx = idx
                  size = 1

                  if @uniform_range
                     size = @max_range_length
                     cur = str[ idx...(idx+size) ]
                     idx = idx + size
                  else
                     found = false
                     while !found && size <= @max_range_length
                        ranges = @ranges[ size ]
                        cur = str[ idx...(idx+size) ]

                        range = ranges.detect {|r| r.contains( cur ) }
                        if !range.nil?
                           found = true
                           idx = idx + size
                        else
                           cur = nil
                           size = size + 1
                        end
                     end
                  end

                  if cur.nil?
                     raise "Could not decode string"
                  end

                  ### At this point cur should be our string we need to do a lookup ###
                  to_append = []
                  if @cidmap.has_key?( cur )
                     to_append = @cidmap[ cur ].value.each_char.each_slice( size ).map(&:join)
                  else
                     to_append = [ cur ]
                  end

                  ### now we have to convert our bytes into unicode stuff ###
                  to_append.each do |th|
                     ## We have to convert each 'bytestring' into a unicode character
                     ## todo this, we reverse them starting with lowest byte and calculate the integer value of the byte string
                     ## then pass this through to pack to turn it into a unicode character
                     output += [ th.reverse.each_char.each_with_index.map{|ch, idx| ch.ord << ( idx * 8 ) }.reduce( 0, :+ ) ].pack( 'U' )
                  end

               end

               output
            end
        end

        class Type0 < Font

            field   :BaseFont,              :Type => Name, :Required => true
            field   :Subtype,               :Type => Name, :Default => :Type0, :Required => true
            field   :DescendantFonts,       :Type => Array.of( Reference )
            field   :Encoding,              :Type => Name

            def decode_text text
               build_cmap!

               @cmap.decode( text )
            end

            def descendant_font
               @_df unless @_df.nil?

               @_df = self.DescendantFonts.first.solve
            end

            def local_font_file
               if !self.descendant_font.FontDescriptor.nil?
                  if self.descendant_font.FontDescriptor.FontFile1
                     self.descendant_font.FontDescriptor.FontFile1
                  elsif self.descendant_font.FontDescriptor.FontFile2
                     self.descendant_font.FontDescriptor.FontFile2
                  elsif self.descendant_font.FontDescriptor.FontFile3
                     self.descendant_font.FontDescriptor.FontFile3
                  end
               end
            end

            def bbox
               descendant_font.bbox
            end

            def units_per_em
               descendant_font.units_per_em
            end

            def glyph_bbox character
               descendant_font.glyph_bbox character
            end

            def glyph_advance character
               descendant_font.glyph_advance character
            end

            def glyph_kerning char1, char2
               descendant_font.glyph_kerning char1, char2
            end

            def build_cmap!
               return if @cmap_built

               @cmap_built = true
               @cmap = CMap.new( self.ToUnicode, self )
            end

            def my_cmap
               @cmap
            end

        end
        #
        # Type1 Fonts.
        #
        class Type1 < Font

            field   :BaseFont,              :Type => Name, :Required => true
            field   :Subtype,               :Type => Name, :Default => :Type1, :Required => true

            #
            # 14 standard Type1 fonts.
            #
            module Standard

                class TimesRoman < Type1
                    field   :BaseFont,          :Type => Name, :Default => :"Times-Roman", :Required => true
                end

                class Helvetica < Type1
                    field   :BaseFont,          :Type => Name, :Default => :Helvetica, :Required => true
                end

                class Courier < Type1
                    field   :BaseFont,          :Type => Name, :Default => :Courier, :Required => true
                end

                class Symbol < Type1
                    field   :BaseFont,          :Type => Name, :Default => :Symbol, :Required => true
                end

                class TimesBold < Type1
                    field   :BaseFont,          :Type => Name, :Default => :"Times-Bold", :Required => true
                end

                class HelveticaBold < Type1
                    field   :BaseFont,          :Type => Name, :Default => :"Helvetica-Bold", :Required => true
                end

                class CourierBold < Type1
                    field   :BaseFont,          :Type => Name, :Default => :"Courier-Bold", :Required => true
                end

                class ZapfDingbats < Type1
                    field   :BaseFont,          :Type => Name, :Default => :ZapfDingbats, :Required => true
                end

                class TimesItalic < Type1
                    field   :BaseFont,          :Type => Name, :Default => :"Times-Italic", :Required => true
                end

                class HelveticaOblique < Type1
                    field   :BaseFont,          :Type => Name, :Default => :"Helvetica-Oblique", :Required => true
                end

                class CourierOblique < Type1
                    field   :BaseFont,          :Type => Name, :Default => :"Courier-Oblique", :Required => true
                end

                class TimesBoldItalic < Type1
                    field   :BaseFont,          :Type => Name, :Default => :"Times-BoldItalic", :Required => true
                end

                class HelveticaBoldOblique < Type1
                    field   :BaseFont,          :Type => Name, :Default => :"Helvetica-BoldOblique", :Required => true
                end

                class CourierBoldOblique < Type1
                    field   :BaseFont,          :Type => Name, :Default => :"Courier-BoldOblique", :Required => true
                end
            end
        end

        #
        # TrueType Fonts
        #
        class TrueType < Font
            field   :Subtype,               :Type => Name, :Default => :TrueType, :Required => true
            field   :BaseFont,              :Type => Name, :Required => true
        end

        #
        # Type 3 Fonts
        #
        ## This is not well supported yet ##
        class Type3 < Font
            include ResourcesHolder

            field   :Subtype,               :Type => Name, :Default => :Type3, :Required => true
            field   :FontBBox,              :Type => Rectangle, :Required => true
            field   :FontMatrix,            :Type => Array.of(Number, length: 6), :Required => true
            field   :CharProcs,             :Type => Dictionary, :Required => true
            field   :Resources,             :Type => Resources, :Version => "1.2"

            def decode_text text
               #raise "Type 3 font unsupported"
               text.unpack('C*').pack('U*')
            end

            def bbox
               #raise "Type 3 font unsupported"
               glyph_bbox " "
            end

            def units_per_em
               #raise "Type 3 font unsupported"
               1000
            end

            def glyph_kerning char1, char2
               #raise "Type 3 font unsupported"
               0.0
            end

            def glyph_advance character
               #raise "Type 3 font unsupported"
               units_per_em
            end

            def glyph_bbox character
               #raise "Type 3 font unsupported"
               [ 0, 0, units_per_em, units_per_em ]
            end
        end
    end

end
