with Ada.Streams;
with Interfaces;
with Tarlib.Errors;

package Tarlib.Internal.Fields
  with Pure
is
   --  Fixed-width ASCII octal field encoding.

   type Field_Terminator is (NUL_Terminated, Checksum_Terminated);
   --  Terminator policy. Checksum fields use NUL followed by space.

   procedure Clear (Field : out Ada.Streams.Stream_Element_Array);
   --  Fill Field with NUL bytes.
   --  @param Field Destination field.

   procedure Put_String
     (Field  : in out Ada.Streams.Stream_Element_Array;
      Text   : String;
      Result : out Tarlib.Errors.Status);
   --  Copy Text into Field and NUL-pad the rest.
   --  @param Field Fixed-width destination field.
   --  @param Text ASCII text without embedded NUL.
   --  @param Result Success or Invalid_Metadata when Text does not fit.

   procedure Put_Octal
     (Field      : in out Ada.Streams.Stream_Element_Array;
      Value      : Interfaces.Unsigned_64;
      Terminator : Field_Terminator;
      Result     : out Tarlib.Errors.Status);
   --  Encode Value as leading-zero ASCII octal in Field.
   --  @param Field Fixed-width destination field.
   --  @param Value Non-negative value to encode.
   --  @param Terminator Field terminator policy.
   --  @param Result Success or Numeric_Field_Overflow.

   function Text_Length
     (Field : Ada.Streams.Stream_Element_Array) return Natural;
   --  Return bytes before the first NUL in Field.
   --  @param Field Fixed-width source field.
   --  @return Number of non-NUL bytes before terminator or Field'Length.

   procedure Get_Octal
     (Field  : Ada.Streams.Stream_Element_Array;
      Value  : out Interfaces.Unsigned_64;
      Result : out Tarlib.Errors.Status);
   --  Decode an ASCII octal field.
   --  @param Field Fixed-width source field.
   --  @param Value Parsed unsigned value.
   --  @param Result Success or Invalid_Archive.

   procedure Get_Numeric
     (Field  : Ada.Streams.Stream_Element_Array;
      Value  : out Interfaces.Unsigned_64;
      Result : out Tarlib.Errors.Status);
   --  Decode an ASCII octal or positive base-256 numeric field.
   --  @param Field Fixed-width source field.
   --  @param Value Parsed unsigned value.
   --  @param Result Success or Invalid_Archive.
end Tarlib.Internal.Fields;
