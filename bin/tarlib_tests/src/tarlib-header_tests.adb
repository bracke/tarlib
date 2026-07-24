with Ada.Streams;
with AUnit.Assertions;
with Tarlib.Entries;
with Tarlib.Errors;
with Tarlib.Internal.Checksums;
with Tarlib.Internal.Fields;
with Tarlib.Internal.Headers;
with Tarlib.Test_Fixtures;

package body Tarlib.Header_Tests is
   use AUnit.Assertions;
   use type Ada.Streams.Stream_Element;
   use type Tarlib.Entries.Entry_Kind;
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

   procedure Test_Contiguous_File_Parses_As_Regular
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Header : Ada.Streams.Stream_Element_Array (1 .. 512);
      Parsed : Tarlib.Internal.Headers.Parsed_Header;
      Result : Tarlib.Errors.Status;
   begin
      Tarlib.Internal.Headers.Build
        ("contiguous.bin", Tarlib.Entries.Regular_File, 4,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File),
         Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "header builds");

      Header (149 .. 156) := [others => 32];
      Header (157) := Character'Pos ('7');
      Tarlib.Internal.Fields.Put_Octal
        (Header (149 .. 156),
         Tarlib.Internal.Checksums.Compute (Header),
         Tarlib.Internal.Fields.Checksum_Terminated, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "checksum stored");

      Tarlib.Internal.Headers.Parse (Header, Parsed, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "contiguous parses");
      Assert
        (Parsed.Kind = Tarlib.Entries.Regular_File,
         "contiguous file kind is regular");
      Assert (Parsed.Size = 4, "contiguous file size");
   end Test_Contiguous_File_Parses_As_Regular;

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

   procedure Test_Header_Owner_Names
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Header   : Ada.Streams.Stream_Element_Array (1 .. 512);
      Parsed   : Tarlib.Internal.Headers.Parsed_Header;
      Result   : Tarlib.Errors.Status;
      Metadata : Tarlib.Entries.Metadata :=
        Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File);
   begin
      Tarlib.Entries.Set_Text (Metadata.User_Name, "alice", Result);
      Assert (Result.Code = Tarlib.Errors.Success, "user name set");
      Tarlib.Entries.Set_Text (Metadata.Group_Name, "staff", Result);
      Assert (Result.Code = Tarlib.Errors.Success, "group name set");

      Tarlib.Internal.Headers.Build
        ("owned.txt", Tarlib.Entries.Regular_File, 0, Metadata,
         Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "owner header builds");
      Assert
        (Tarlib.Test_Fixtures.Field_Text (Header, 266, 271) =
         "alice" & Character'Val (0),
         "USTAR user name");
      Assert
        (Tarlib.Test_Fixtures.Field_Text (Header, 298, 303) =
         "staff" & Character'Val (0),
         "USTAR group name");

      Tarlib.Internal.Headers.Parse (Header, Parsed, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "owner header parses");
      Assert
        (Tarlib.Entries.Text (Parsed.Metadata.User_Name) = "alice",
         "parsed user name");
      Assert
        (Tarlib.Entries.Text (Parsed.Metadata.Group_Name) = "staff",
         "parsed group name");
   end Test_Header_Owner_Names;

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

   procedure Test_Maximum_Prefix_Path_Parse
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Header : Ada.Streams.Stream_Element_Array (1 .. 512);
      Parsed : Tarlib.Internal.Headers.Parsed_Header;
      Result : Tarlib.Errors.Status;
      Path   : constant String := Repeat ('a', 155) & "/" & Repeat ('b', 100);
   begin
      Tarlib.Internal.Headers.Build
        (Path, Tarlib.Entries.Regular_File, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File),
         Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "maximum path builds");

      Tarlib.Internal.Headers.Parse (Header, Parsed, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "maximum path parses");
      Assert (Parsed.Path_Length = Path'Length, "maximum path length");
      Assert
        (Parsed.Path_Text (1 .. Parsed.Path_Length) = Path,
         "maximum path text");
   end Test_Maximum_Prefix_Path_Parse;

   procedure Test_Link_Header (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Header : Ada.Streams.Stream_Element_Array (1 .. 512);
      Parsed : Tarlib.Internal.Headers.Parsed_Header;
      Result : Tarlib.Errors.Status;
      Long_Target : constant String := Repeat ('t', 100);
      Too_Long_Target : constant String := Repeat ('u', 101);
   begin
      Tarlib.Internal.Headers.Build
        ("link.txt", Tarlib.Entries.Symbolic_Link, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Symbolic_Link),
         "target.txt", Header, Result);

      Assert (Result.Code = Tarlib.Errors.Success, "symbolic link header");
      Assert (Header (157) = Character'Pos ('2'), "symbolic link type flag");
      Assert
        (Tarlib.Test_Fixtures.Field_Text (Header, 158, 168) =
         "target.txt" & Character'Val (0),
         "symbolic link target");
      Assert
        (Tarlib.Test_Fixtures.Field_Text (Header, 125, 136) =
         "00000000000" & Character'Val (0),
         "symbolic link size");

      Tarlib.Internal.Headers.Build
        ("bad-link", Tarlib.Entries.Symbolic_Link, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Symbolic_Link),
         "", Header, Result);
      Assert
        (Result.Code = Tarlib.Errors.Invalid_Metadata,
         "empty link target rejected");

      Tarlib.Internal.Headers.Build
        ("max-link", Tarlib.Entries.Symbolic_Link, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Symbolic_Link),
         Long_Target, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "maximum link target");
      Tarlib.Internal.Headers.Parse (Header, Parsed, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "maximum link parses");
      Assert (Parsed.Link_Length = Long_Target'Length, "maximum link length");
      Assert
        (Parsed.Link_Text (1 .. Parsed.Link_Length) = Long_Target,
         "maximum link text");

      Tarlib.Internal.Headers.Build
        ("too-long-link", Tarlib.Entries.Symbolic_Link, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Symbolic_Link),
         Too_Long_Target, Header, Result);
      Assert
        (Result.Code = Tarlib.Errors.Invalid_Metadata,
         "overlong raw link target rejected");
   end Test_Link_Header;

   procedure Test_Special_Header (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Header : Ada.Streams.Stream_Element_Array (1 .. 512);
      Result : Tarlib.Errors.Status;
      Device : constant Tarlib.Entries.Device_Numbers :=
        (Major => 8#12#, Minor => 8#34#);
   begin
      Tarlib.Internal.Headers.Build
        ("dev/tty0", Tarlib.Entries.Character_Device, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Character_Device),
         "", Device, Header, Result);

      Assert (Result.Code = Tarlib.Errors.Success, "character device header");
      Assert (Header (157) = Character'Pos ('3'), "character device flag");
      Assert
        (Tarlib.Test_Fixtures.Field_Text (Header, 330, 337) =
         "0000012" & Character'Val (0),
         "major number");
      Assert
        (Tarlib.Test_Fixtures.Field_Text (Header, 338, 345) =
         "0000034" & Character'Val (0),
         "minor number");

      Tarlib.Internal.Headers.Build
        ("pipe", Tarlib.Entries.FIFO, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.FIFO),
         "", Tarlib.Entries.No_Device, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "fifo header");
      Assert (Header (157) = Character'Pos ('6'), "fifo flag");

      Tarlib.Internal.Headers.Build
        ("pipe", Tarlib.Entries.FIFO, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.FIFO),
         "", Device, Header, Result);
      Assert
        (Result.Code = Tarlib.Errors.Invalid_Metadata,
         "non-device numbers rejected");
   end Test_Special_Header;

   overriding procedure Register_Tests (T : in out Test_Case) is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine
        (T, Test_File_Header'Access, "regular file header fields");
      Registration.Register_Routine
        (T, Test_Contiguous_File_Parses_As_Regular'Access,
         "contiguous file parses as regular");
      Registration.Register_Routine
        (T, Test_Directory_Header'Access, "directory header fields");
      Registration.Register_Routine
        (T, Test_Header_Owner_Names'Access, "header owner names");
      Registration.Register_Routine
        (T, Test_Prefix_Header'Access, "prefix field header");
      Registration.Register_Routine
        (T, Test_Maximum_Prefix_Path_Parse'Access,
         "maximum prefix path parse");
      Registration.Register_Routine
        (T, Test_Link_Header'Access, "link header fields");
      Registration.Register_Routine
        (T, Test_Special_Header'Access, "special header fields");
   end Register_Tests;
end Tarlib.Header_Tests;
