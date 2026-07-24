with Ada.Streams;
with AUnit.Assertions;
with Tarlib.Entries;
with Tarlib.Errors;
with Tarlib.Internal.Checksums;
with Tarlib.Internal.Headers;
with Tarlib.Test_Fixtures;

package body Tarlib.Header_Tests is
   use AUnit.Assertions;
   use type Ada.Streams.Stream_Element;
   use type Tarlib.Errors.Status_Code;
   use type Tarlib.Internal.Checksums.Checksum_Value;

   overriding function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("USTAR header construction");
   end Name;

   function Repeat (Ch : Character; Count : Natural) return String is
      Result : String (1 .. Count);
   begin
      for Index in Result'Range loop
         Result (Index) := Ch;
      end loop;
      return Result;
   end Repeat;

   procedure Test_File_Header (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Header : Ada.Streams.Stream_Element_Array (1 .. 512);
      Result : Tarlib.Errors.Status;
      Sum    : Tarlib.Internal.Checksums.Checksum_Value;
   begin
      Tarlib.Internal.Headers.Build
        ("dir/file.txt", Tarlib.Entries.Regular_File, 11,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File),
         Header, Result);

      Assert (Result.Code = Tarlib.Errors.Success, "file header builds");
      Assert
        (Tarlib.Test_Fixtures.Field_Text (Header, 1, 13) = "dir/file.txt" & Character'Val (0),
         "name field");
      Assert
        (Tarlib.Test_Fixtures.Field_Text (Header, 101, 108) = "0000644" & Character'Val (0),
         "file mode");
      Assert
        (Tarlib.Test_Fixtures.Field_Text (Header, 109, 116) = "0000000" & Character'Val (0),
         "uid default");
      Assert
        (Tarlib.Test_Fixtures.Field_Text (Header, 117, 124) = "0000000" & Character'Val (0),
         "gid default");
      Assert
        (Tarlib.Test_Fixtures.Field_Text (Header, 125, 136) = "00000000013" & Character'Val (0),
         "size field");
      Assert
        (Tarlib.Test_Fixtures.Field_Text (Header, 137, 148) = "00000000000" & Character'Val (0),
         "mtime default");
      Assert (Header (157) = Character'Pos ('0'), "regular type flag");
      Assert
        (Tarlib.Test_Fixtures.Field_Text (Header, 258, 263) = "ustar" & Character'Val (0),
         "magic");
      Assert (Header (264) = Character'Pos ('0'), "version first byte");
      Assert (Header (265) = Character'Pos ('0'), "version second byte");
      Sum := Tarlib.Internal.Checksums.Compute (Header);
      Assert (Sum > 0, "checksum is nonzero");
      Assert
        (Tarlib.Test_Fixtures.Field_Text (Header, 149, 156) (7) = Character'Val (0),
         "checksum NUL terminator");
   end Test_File_Header;

   procedure Test_Directory_Header
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Header : Ada.Streams.Stream_Element_Array (1 .. 512);
      Result : Tarlib.Errors.Status;
   begin
      Tarlib.Internal.Headers.Build
        ("dir/", Tarlib.Entries.Directory, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Directory),
         Header, Result);

      Assert (Result.Code = Tarlib.Errors.Success, "directory header builds");
      Assert (Header (157) = Character'Pos ('5'), "directory type flag");
      Assert
        (Tarlib.Test_Fixtures.Field_Text (Header, 101, 108) = "0000755" & Character'Val (0),
         "directory mode");
      Assert
        (Tarlib.Test_Fixtures.Field_Text (Header, 125, 136) = "00000000000" & Character'Val (0),
         "directory size");
   end Test_Directory_Header;

   procedure Test_Prefix_Header (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Header : Ada.Streams.Stream_Element_Array (1 .. 512);
      Result : Tarlib.Errors.Status;
      Path   : constant String :=
        Repeat ('a', 80) & "/" & Repeat ('b', 40) & "/file.txt";
   begin
      Tarlib.Internal.Headers.Build
        (Path, Tarlib.Entries.Regular_File, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File),
         Header, Result);

      Assert (Result.Code = Tarlib.Errors.Success, "prefix header builds");
      Assert
        (Tarlib.Test_Fixtures.Field_Text (Header, 1, 8) = "file.txt",
         "name suffix field");
      Assert
        (Header (346) = Character'Pos ('a'),
         "prefix field starts with directory path");
   end Test_Prefix_Header;

   overriding procedure Register_Tests (T : in out Test_Case) is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine
        (T, Test_File_Header'Access, "regular file header fields");
      Registration.Register_Routine
        (T, Test_Directory_Header'Access, "directory header fields");
      Registration.Register_Routine
        (T, Test_Prefix_Header'Access, "prefix field header");
   end Register_Tests;
end Tarlib.Header_Tests;
