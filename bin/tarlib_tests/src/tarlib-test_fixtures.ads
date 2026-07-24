with Ada.Streams;

package Tarlib.Test_Fixtures is
   function To_Bytes (Text : String) return Ada.Streams.Stream_Element_Array;

   function Is_Zero_Block
     (Data  : Ada.Streams.Stream_Element_Array;
      First : Ada.Streams.Stream_Element_Offset) return Boolean;

   function Field_Text
     (Data  : Ada.Streams.Stream_Element_Array;
      First : Ada.Streams.Stream_Element_Offset;
      Last  : Ada.Streams.Stream_Element_Offset) return String;
end Tarlib.Test_Fixtures;
