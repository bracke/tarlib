with Ada.Streams;

package body Tarlib.Test_Fixtures is
   use type Ada.Streams.Stream_Element_Offset;
   use type Ada.Streams.Stream_Element;

   function To_Bytes (Text : String) return Ada.Streams.Stream_Element_Array is
      Result : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Text'Length));
   begin
      for Index in Result'Range loop
         Result (Index) :=
           Ada.Streams.Stream_Element
             (Character'Pos (Text (Text'First + Natural (Index - Result'First))));
      end loop;
      return Result;
   end To_Bytes;

   function Is_Zero_Block
     (Data  : Ada.Streams.Stream_Element_Array;
      First : Ada.Streams.Stream_Element_Offset) return Boolean is
   begin
      for Index in First .. First + 511 loop
         if Data (Index) /= 0 then
            return False;
         end if;
      end loop;
      return True;
   end Is_Zero_Block;

   function Field_Text
     (Data  : Ada.Streams.Stream_Element_Array;
      First : Ada.Streams.Stream_Element_Offset;
      Last  : Ada.Streams.Stream_Element_Offset) return String
   is
      Result : String (1 .. Natural (Last - First + 1));
   begin
      for Index in Result'Range loop
         Result (Index) :=
           Character'Val (Data (First + Ada.Streams.Stream_Element_Offset (Index - 1)));
      end loop;
      return Result;
   end Field_Text;
end Tarlib.Test_Fixtures;
