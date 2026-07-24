with Ada.Streams;
with AUnit.Assertions;
with Interfaces;
with Tarlib.Errors;
with Tarlib.Internal.Checksums;
with Tarlib.Internal.Constants;
with Tarlib.Internal.Fields;
with Tarlib.Test_Fixtures;

package body Tarlib.Field_Tests is
   use AUnit.Assertions;
   use type Ada.Streams.Stream_Element;
   use type Interfaces.Integer_64;
   use type Interfaces.Unsigned_64;
   use type Tarlib.Errors.Status_Code;

   overriding function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("USTAR numeric and text fields");
   end Name;

   procedure Test_Octal_Layout (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Field  : Ada.Streams.Stream_Element_Array (1 .. 8);
      Result : Tarlib.Errors.Status;
   begin
      Tarlib.Internal.Fields.Put_Octal
        (Field, 0, Tarlib.Internal.Fields.NUL_Terminated, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "zero encodes");
      Assert
        (Tarlib.Test_Fixtures.Field_Text (Field, 1, 8) = "0000000" & Character'Val (0),
         "zero has leading zeros and NUL");

      Tarlib.Internal.Fields.Put_Octal
        (Field, 8#755#, Tarlib.Internal.Fields.NUL_Terminated, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "typical value encodes");
      Assert
        (Tarlib.Test_Fixtures.Field_Text (Field, 1, 8) = "0000755" & Character'Val (0),
         "typical layout");

      Tarlib.Internal.Fields.Put_Octal
        (Field, 8#7777777#, Tarlib.Internal.Fields.NUL_Terminated, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "maximum encodes");
      Assert
        (Tarlib.Test_Fixtures.Field_Text (Field, 1, 8) = "7777777" & Character'Val (0),
         "maximum layout");

      Tarlib.Internal.Fields.Put_Octal
        (Field, 8#10000000#, Tarlib.Internal.Fields.NUL_Terminated, Result);
      Assert
        (Result.Code = Tarlib.Errors.Numeric_Field_Overflow,
         "overflow is rejected");
   end Test_Octal_Layout;

   procedure Test_Checksum_Terminator
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Field  : Ada.Streams.Stream_Element_Array (1 .. 8);
      Result : Tarlib.Errors.Status;
   begin
      Tarlib.Internal.Fields.Put_Octal
        (Field, 8#1234#, Tarlib.Internal.Fields.Checksum_Terminated, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "checksum value encodes");
      Assert
        (Tarlib.Test_Fixtures.Field_Text (Field, 1, 8) = "001234" & Character'Val (0) & " ",
         "checksum terminator is NUL plus space");
   end Test_Checksum_Terminator;

   procedure Test_Base_256_Numeric
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Field  : Ada.Streams.Stream_Element_Array (1 .. 4) :=
        [16#80#, 0, 1, 0];
      Value  : Interfaces.Unsigned_64;
      Result : Tarlib.Errors.Status;
   begin
      Tarlib.Internal.Fields.Get_Numeric (Field, Value, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "positive base-256 decodes");
      Assert (Value = 256, "base-256 value");

      Field := [16#FF#, 0, 0, 1];
      Tarlib.Internal.Fields.Get_Numeric (Field, Value, Result);
      Assert
        (Result.Code = Tarlib.Errors.Invalid_Archive,
         "negative base-256 rejected");

      declare
         Wide_Field : Ada.Streams.Stream_Element_Array (1 .. 9) :=
           [16#80#, 255, 255, 255, 255, 255, 255, 255, 255];
      begin
         Tarlib.Internal.Fields.Get_Numeric (Wide_Field, Value, Result);
         Assert
           (Result.Code = Tarlib.Errors.Success,
            "largest unsigned base-256 decodes");
         Assert (Value = Interfaces.Unsigned_64'Last, "largest base-256 value");

         Wide_Field := [16#81#, 0, 0, 0, 0, 0, 0, 0, 0];
         Tarlib.Internal.Fields.Get_Numeric (Wide_Field, Value, Result);
         Assert
           (Result.Code = Tarlib.Errors.Invalid_Archive,
            "base-256 overflow rejected");
      end;
   end Test_Base_256_Numeric;

   procedure Test_Signed_Checksum
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Header : Tarlib.Internal.Constants.Header_Block :=
        Tarlib.Internal.Constants.Zero_Block;
   begin
      Header (1) := 16#80#;
      Assert
        (Tarlib.Internal.Checksums.Compute (Header) =
         Tarlib.Internal.Checksums.Checksum_Value (32 * 8 + 128),
         "unsigned checksum includes high byte");
      Assert
        (Tarlib.Internal.Checksums.Compute_Signed (Header) =
         32 * 8 - 128,
         "signed checksum treats high byte as negative");
   end Test_Signed_Checksum;

   procedure Test_Text_Field (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Field  : Ada.Streams.Stream_Element_Array (1 .. 4);
      Result : Tarlib.Errors.Status;
   begin
      Tarlib.Internal.Fields.Put_String (Field, "abc", Result);
      Assert (Result.Code = Tarlib.Errors.Success, "short text encodes");
      Assert (Field (1) = Character'Pos ('a'), "first byte");
      Assert (Field (4) = 0, "NUL padding");

      Tarlib.Internal.Fields.Put_String (Field, "abcde", Result);
      Assert (Result.Code = Tarlib.Errors.Invalid_Metadata, "oversize text rejected");
   end Test_Text_Field;

   overriding procedure Register_Tests (T : in out Test_Case) is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine
        (T, Test_Octal_Layout'Access, "octal field boundaries");
      Registration.Register_Routine
        (T, Test_Checksum_Terminator'Access, "checksum field terminator");
      Registration.Register_Routine
        (T, Test_Base_256_Numeric'Access, "base-256 numeric fields");
      Registration.Register_Routine
        (T, Test_Signed_Checksum'Access, "signed checksum calculation");
      Registration.Register_Routine
        (T, Test_Text_Field'Access, "text field validation");
   end Register_Tests;
end Tarlib.Field_Tests;
