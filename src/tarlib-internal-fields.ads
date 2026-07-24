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
end Tarlib.Internal.Fields;
