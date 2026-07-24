with Ada.Streams;
with AUnit.Assertions;
with Interfaces;
with Tarlib.Entries;
with Tarlib.Errors;
with Tarlib.Internal.Checksums;
with Tarlib.Internal.Constants;
with Tarlib.Internal.Fields;
with Tarlib.Internal.Headers;
with Tarlib.Readers;
with Tarlib.Test_Fixtures;
with Tarlib.Test_Outputs;
with Tarlib.Writers;

package body Tarlib.Reader_Tests is
   use AUnit.Assertions;
   use type Ada.Streams.Stream_Element_Offset;
   use type Ada.Streams.Stream_Element;
   use type Ada.Streams.Stream_Element_Array;
   use type Interfaces.Integer_64;
   use type Tarlib.Byte_Count;
   use type Tarlib.Entries.Device_Number;
   use type Tarlib.Entries.Entry_Kind;
   use type Tarlib.Errors.Status_Code;
   use type Tarlib.Readers.Reader_State;

   function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("TAR archive reader");
   end Name;

   procedure Build_Sample
     (Sink   : in out Tarlib.Test_Outputs.Memory_Sink;
      Result : out Tarlib.Errors.Status)
   is
      Writer : Tarlib.Writers.Writer;
      Data   : constant Ada.Streams.Stream_Element_Array :=
        [Character'Pos ('h'), Character'Pos ('e'), Character'Pos ('l'),
         Character'Pos ('l'), Character'Pos ('o')];
   begin
      Tarlib.Test_Outputs.Reset (Sink);
      Tarlib.Writers.Initialize (Writer, Sink, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Tarlib.Writers.Add_Directory (Writer, "dir/", Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Tarlib.Writers.Begin_File (Writer, "dir/file.txt", 5, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Tarlib.Writers.Write (Writer, Data, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Tarlib.Writers.End_Entry (Writer, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Tarlib.Writers.Add_Symbolic_Link
        (Writer, "dir/latest", "file.txt", Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Tarlib.Writers.Add_Character_Device
        (Writer, "dev/null", (Major => 1, Minor => 3), Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Tarlib.Writers.Add_FIFO (Writer, "run/pipe", Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Tarlib.Writers.Finish (Writer, Result);
      Tarlib.Test_Outputs.Rewind (Sink);
   end Build_Sample;

   procedure Write_Terminator
     (Sink   : in out Tarlib.Test_Outputs.Memory_Sink;
      Result : out Tarlib.Errors.Status)
   is
   begin
      Tarlib.Test_Outputs.Write
        (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Tarlib.Test_Outputs.Write
        (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
   end Write_Terminator;

   procedure Test_Empty_Archive (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);

      Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
      Writer    : Tarlib.Writers.Writer;
      Reader    : Tarlib.Readers.Reader;
      Info     : Tarlib.Readers.Entry_Info;
      Result    : Tarlib.Errors.Status;
      Has_Entry : Boolean;
   begin
      Tarlib.Writers.Initialize (Writer, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "writer initialize");
      Tarlib.Writers.Finish (Writer, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "writer finish");
      Tarlib.Test_Outputs.Rewind (Sink);

      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");
      Assert (not Tarlib.Readers.At_End (Reader), "not at end before read");
      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "empty archive read");
      Assert (not Has_Entry, "no entry");
      Assert (Tarlib.Readers.State (Reader) = Tarlib.Readers.Finished, "finished");
      Assert (Tarlib.Readers.At_End (Reader), "at end after terminator");

      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "repeat end read");
      Assert (not Has_Entry, "still no entry");
      Assert (Tarlib.Readers.At_End (Reader), "still at end");
   end Test_Empty_Archive;

   procedure Test_Single_Zero_Block_Terminates
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
      Reader    : Tarlib.Readers.Reader;
      Info      : Tarlib.Readers.Entry_Info;
      Result    : Tarlib.Errors.Status;
      Has_Entry : Boolean;
      Garbage   : constant Ada.Streams.Stream_Element_Array (1 .. 512) :=
        [others => Character'Pos ('x')];
   begin
      Tarlib.Test_Outputs.Write
        (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write zero block");
      Tarlib.Test_Outputs.Write (Sink, Garbage, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write trailing garbage");
      Tarlib.Test_Outputs.Rewind (Sink);

      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");
      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "terminator read");
      Assert (not Has_Entry, "no entry");
      Assert
        (Tarlib.Readers.State (Reader) = Tarlib.Readers.Finished,
         "finished at first zero block");
      Assert (Tarlib.Readers.At_End (Reader), "at end");
   end Test_Single_Zero_Block_Terminates;

   procedure Test_Read_File_Content
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
      Reader    : Tarlib.Readers.Reader;
      Info     : Tarlib.Readers.Entry_Info;
      Result    : Tarlib.Errors.Status;
      Has_Entry : Boolean;
      Data      : Ada.Streams.Stream_Element_Array (1 .. 8);
      Last      : Ada.Streams.Stream_Element_Offset;
   begin
      Build_Sample (Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "sample archive builds");

      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");

      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "directory header");
      Assert (Has_Entry, "directory found");
      Assert (Tarlib.Readers.Path (Info) = "dir/", "directory path");
      Assert
        (Tarlib.Readers.Kind (Info) = Tarlib.Entries.Directory,
         "directory kind");

      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "file header");
      Assert (Has_Entry, "file found");
      Assert (Tarlib.Readers.Path (Info) = "dir/file.txt", "file path");
      Assert (Tarlib.Readers.Size (Info) = 5, "file size");

      Tarlib.Readers.Read (Reader, Data, Last, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "file content read");
      Assert (Last = 5, "five bytes read");
      Assert (Data (1) = Character'Pos ('h'), "first byte");
      Assert (Data (5) = Character'Pos ('o'), "last byte");

      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "symbolic link header");
      Assert (Has_Entry, "symbolic link found");
      Assert (Tarlib.Readers.Path (Info) = "dir/latest", "link path");
      Assert
        (Tarlib.Readers.Kind (Info) = Tarlib.Entries.Symbolic_Link,
         "symbolic link kind");
      Assert (Tarlib.Readers.Link_Path (Info) = "file.txt", "link target");

      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "device header");
      Assert (Has_Entry, "device found");
      Assert (Tarlib.Readers.Path (Info) = "dev/null", "device path");
      Assert
        (Tarlib.Readers.Kind (Info) = Tarlib.Entries.Character_Device,
         "device kind");
      Assert (Tarlib.Readers.Device (Info).Major = 1, "device major");
      Assert (Tarlib.Readers.Device (Info).Minor = 3, "device minor");

      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "fifo header");
      Assert (Has_Entry, "fifo found");
      Assert (Tarlib.Readers.Path (Info) = "run/pipe", "fifo path");
      Assert (Tarlib.Readers.Kind (Info) = Tarlib.Entries.FIFO, "fifo kind");

      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "archive terminator");
      Assert (not Has_Entry, "no more entries");
   end Test_Read_File_Content;

   procedure Test_Directory_Read_Rejected
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
      Reader    : Tarlib.Readers.Reader;
      Info     : Tarlib.Readers.Entry_Info;
      Result    : Tarlib.Errors.Status;
      Has_Entry : Boolean;
      Data      : Ada.Streams.Stream_Element_Array (1 .. 1);
      Last      : Ada.Streams.Stream_Element_Offset;
   begin
      Build_Sample (Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "sample archive builds");

      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert (Result.Code = Tarlib.Errors.Success and then Has_Entry, "directory");

      Tarlib.Readers.Read (Reader, Data, Last, Result);
      Assert
        (Result.Code = Tarlib.Errors.Invalid_Entry_Kind,
         "directory content rejected");
   end Test_Directory_Read_Rejected;

   procedure Test_Invalid_Checksum
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
      Reader    : Tarlib.Readers.Reader;
      Info     : Tarlib.Readers.Entry_Info;
      Result    : Tarlib.Errors.Status;
      Has_Entry : Boolean;
      Data      : Ada.Streams.Stream_Element_Array (1 .. 1);
      Last      : Ada.Streams.Stream_Element_Offset;
   begin
      Build_Sample (Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "sample archive builds");

      Tarlib.Test_Outputs.Set_Element (Sink, 1, Character'Pos ('x'));
      Tarlib.Test_Outputs.Rewind (Sink);
      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");
      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert (Result.Code /= Tarlib.Errors.Success, "invalid archive rejected");
      Assert
        (Tarlib.Readers.State (Reader) = Tarlib.Readers.Failed,
         "reader enters failed state");

      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert
        (Result.Code = Tarlib.Errors.Input_Failure,
         "next after failure reports input failure");
      Tarlib.Readers.Read (Reader, Data, Last, Result);
      Assert
        (Result.Code = Tarlib.Errors.Input_Failure,
         "read after failure reports input failure");
      Tarlib.Readers.Skip_Entry (Reader, Result);
      Assert
        (Result.Code = Tarlib.Errors.Input_Failure,
         "skip after failure reports input failure");
   end Test_Invalid_Checksum;

   function Repeat (Ch : Character; Count : Natural) return String is
      Result : String (1 .. Count);
   begin
      for Index in Result'Range loop
         Result (Index) := Ch;
      end loop;
      return Result;
   end Repeat;

   procedure Test_PAX_Long_Path (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);

      Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
      Writer    : Tarlib.Writers.Writer;
      Reader    : Tarlib.Readers.Reader;
      Info      : Tarlib.Readers.Entry_Info;
      Result    : Tarlib.Errors.Status;
      Has_Entry : Boolean;
      Long_Path : constant String :=
        "long/" & Repeat ('a', 120) & "/" & Repeat ('b', 120) & "/file.txt";
      Data      : constant Ada.Streams.Stream_Element_Array :=
        [Character'Pos ('x')];
      Buffer    : Ada.Streams.Stream_Element_Array (1 .. 1);
      Last      : Ada.Streams.Stream_Element_Offset;
   begin
      Tarlib.Writers.Initialize (Writer, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "writer initialize");
      Tarlib.Writers.Begin_File (Writer, Long_Path, 1, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "begin long path file");
      Tarlib.Writers.Write (Writer, Data, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write long path content");
      Tarlib.Writers.End_Entry (Writer, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "end long path file");
      Tarlib.Writers.Finish (Writer, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "finish long path archive");

      Tarlib.Test_Outputs.Rewind (Sink);
      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");
      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "read PAX path entry");
      Assert (Has_Entry, "long path entry found");
      Assert (Tarlib.Readers.Path (Info) = Long_Path, "PAX path override");
      Assert (Tarlib.Readers.Size (Info) = 1, "PAX file size");
      Tarlib.Readers.Read (Reader, Buffer, Last, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "read PAX file content");
      Assert (Last = 1 and then Buffer (1) = Character'Pos ('x'), "content");
   end Test_PAX_Long_Path;

   procedure Test_PAX_Long_Link_Path
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
      Writer    : Tarlib.Writers.Writer;
      Reader    : Tarlib.Readers.Reader;
      Info      : Tarlib.Readers.Entry_Info;
      Result    : Tarlib.Errors.Status;
      Has_Entry : Boolean;
      Target    : constant String :=
        "targets/" & Repeat ('c', 120) & "/" & Repeat ('d', 120);
   begin
      Tarlib.Writers.Initialize (Writer, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "writer initialize");
      Tarlib.Writers.Add_Symbolic_Link
        (Writer, "latest", Target, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "long symbolic link");
      Tarlib.Writers.Finish (Writer, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "finish link archive");

      Tarlib.Test_Outputs.Rewind (Sink);
      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");
      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "read PAX linkpath entry");
      Assert (Has_Entry, "link entry found");
      Assert
        (Tarlib.Readers.Kind (Info) = Tarlib.Entries.Symbolic_Link,
         "symbolic link kind");
      Assert (Tarlib.Readers.Path (Info) = "latest", "link path");
      Assert (Tarlib.Readers.Link_Path (Info) = Target, "PAX linkpath");
   end Test_PAX_Long_Link_Path;

   procedure Test_PAX_Long_Non_File_Paths
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
      Writer    : Tarlib.Writers.Writer;
      Reader    : Tarlib.Readers.Reader;
      Info      : Tarlib.Readers.Entry_Info;
      Result    : Tarlib.Errors.Status;
      Has_Entry : Boolean;
      Dir_Path  : constant String :=
        "dirs/" & Repeat ('e', 120) & "/" & Repeat ('f', 120) & "/";
      Link_Path : constant String :=
        "links/" & Repeat ('g', 120) & "/" & Repeat ('h', 120);
      FIFO_Path : constant String :=
        "pipes/" & Repeat ('i', 120) & "/" & Repeat ('j', 120);
   begin
      Tarlib.Writers.Initialize (Writer, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "writer initialize");
      Tarlib.Writers.Add_Directory (Writer, Dir_Path, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "long directory path");
      Tarlib.Writers.Add_Symbolic_Link
        (Writer, Link_Path, "target", Result);
      Assert (Result.Code = Tarlib.Errors.Success, "long link entry path");
      Tarlib.Writers.Add_FIFO (Writer, FIFO_Path, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "long fifo path");
      Tarlib.Writers.Finish (Writer, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "finish archive");

      Tarlib.Test_Outputs.Rewind (Sink);
      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");

      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert (Result.Code = Tarlib.Errors.Success and then Has_Entry, "dir");
      Assert (Tarlib.Readers.Path (Info) = Dir_Path, "PAX directory path");
      Assert (Tarlib.Readers.Kind (Info) = Tarlib.Entries.Directory, "dir kind");

      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert (Result.Code = Tarlib.Errors.Success and then Has_Entry, "link");
      Assert (Tarlib.Readers.Path (Info) = Link_Path, "PAX link entry path");
      Assert
        (Tarlib.Readers.Kind (Info) = Tarlib.Entries.Symbolic_Link,
         "link kind");
      Assert (Tarlib.Readers.Link_Path (Info) = "target", "link target");

      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert (Result.Code = Tarlib.Errors.Success and then Has_Entry, "fifo");
      Assert (Tarlib.Readers.Path (Info) = FIFO_Path, "PAX fifo path");
      Assert (Tarlib.Readers.Kind (Info) = Tarlib.Entries.FIFO, "fifo kind");
   end Test_PAX_Long_Non_File_Paths;

   procedure Test_PAX_Numeric_Overrides
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
      Writer    : Tarlib.Writers.Writer;
      Reader    : Tarlib.Readers.Reader;
      Info      : Tarlib.Readers.Entry_Info;
      Result    : Tarlib.Errors.Status;
      Has_Entry : Boolean;
      Header    : Ada.Streams.Stream_Element_Array (1 .. 512);
      PAX_Data  : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes
          ("9 size=3" & Character'Val (10)
           & "14 mtime=1234" & Character'Val (10)
           & "9 uid=42" & Character'Val (10)
           & "9 gid=77" & Character'Val (10));
      Payload   : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes ("abc");
      Buffer    : Ada.Streams.Stream_Element_Array (1 .. 3);
      Last      : Ada.Streams.Stream_Element_Offset;
      Meta      : Tarlib.Entries.Metadata;
   begin
      Tarlib.Writers.Initialize (Writer, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "writer initialize");

      Tarlib.Internal.Headers.Build
        ("PaxHeaders/numeric", Tarlib.Entries.PAX_Extended_Header,
         Tarlib.Byte_Count (PAX_Data'Length),
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.PAX_Extended_Header),
         Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "PAX header builds");
      Tarlib.Writers.Begin_File (Writer, "placeholder", 0, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "placeholder file");
      Tarlib.Writers.End_Entry (Writer, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "placeholder end");

      Tarlib.Test_Outputs.Reset (Sink);
      Tarlib.Test_Outputs.Write (Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write PAX header");
      Tarlib.Test_Outputs.Write (Sink, PAX_Data, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write PAX data");
      Tarlib.Test_Outputs.Write
        (Sink,
         [1 .. 512 - Ada.Streams.Stream_Element_Offset (PAX_Data'Length) =>
            0],
         Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write PAX padding");
      Tarlib.Internal.Headers.Build
        ("file.txt", Tarlib.Entries.Regular_File, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File),
         Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "file header builds");
      Tarlib.Test_Outputs.Write (Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write file header");
      Tarlib.Test_Outputs.Write (Sink, Payload, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write payload");
      Tarlib.Test_Outputs.Write (Sink, [1 .. 509 => 0], Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write payload padding");
      Tarlib.Test_Outputs.Write
        (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "first terminator");
      Tarlib.Test_Outputs.Write
        (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "second terminator");

      Tarlib.Test_Outputs.Rewind (Sink);
      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");
      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert (Result.Code = Tarlib.Errors.Success and then Has_Entry, "entry");
      Assert (Tarlib.Readers.Size (Info) = 3, "PAX size override");
      Meta := Tarlib.Readers.Metadata (Info);
      Assert (Meta.MTime = 1234, "PAX mtime override");
      Assert (Meta.ATime = 0, "default atime");
      Assert (Meta.CTime = 0, "default ctime");
      Assert (Meta.UID = 42, "PAX uid override");
      Assert (Meta.GID = 77, "PAX gid override");
      Tarlib.Readers.Read (Reader, Buffer, Last, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "read overridden payload");
      Assert (Last = 3 and then Buffer = Payload, "payload bytes");
   end Test_PAX_Numeric_Overrides;

   procedure Write_PAX_Header
     (Sink   : in out Tarlib.Test_Outputs.Memory_Sink;
      Kind   : Tarlib.Entries.Entry_Kind;
      Data   : Ada.Streams.Stream_Element_Array;
      Result : out Tarlib.Errors.Status);

   procedure Test_PAX_Access_And_Change_Times
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
      Reader    : Tarlib.Readers.Reader;
      Info      : Tarlib.Readers.Entry_Info;
      Result    : Tarlib.Errors.Status;
      Has_Entry : Boolean;
      Header    : Ada.Streams.Stream_Element_Array (1 .. 512);
      Meta      : Tarlib.Entries.Metadata;
      PAX_Data  : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes
          ("15 atime=123.9" & Character'Val (10)
           & "15 ctime=456.1" & Character'Val (10));
   begin
      Write_PAX_Header
        (Sink, Tarlib.Entries.PAX_Extended_Header, PAX_Data, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "time PAX header");
      Tarlib.Internal.Headers.Build
        ("times.txt", Tarlib.Entries.Regular_File, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File),
         Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "file header");
      Tarlib.Test_Outputs.Write (Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write file");
      Tarlib.Test_Outputs.Write
        (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "first terminator");
      Tarlib.Test_Outputs.Write
        (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "second terminator");

      Tarlib.Test_Outputs.Rewind (Sink);
      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");
      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert (Result.Code = Tarlib.Errors.Success and then Has_Entry, "entry");
      Meta := Tarlib.Readers.Metadata (Info);
      Assert (Meta.ATime = 123, "PAX atime truncates");
      Assert (Meta.CTime = 456, "PAX ctime truncates");
   end Test_PAX_Access_And_Change_Times;

   procedure Test_Unknown_PAX_Records
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
      Reader    : Tarlib.Readers.Reader;
      Info      : Tarlib.Readers.Entry_Info;
      Result    : Tarlib.Errors.Status;
      Has_Entry : Boolean;
      Header    : Ada.Streams.Stream_Element_Array (1 .. 512);
      Global    : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes
          ("19 VENDOR.global=x" & Character'Val (10));
      Local     : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes
          ("20 SCHILY.xattr.a=b" & Character'Val (10)
           & "31 SCHILY.acl.access=user::rw-" & Character'Val (10)
           & "33 SCHILY.acl.default=group::r--" & Character'Val (10)
           & "28 LIBARCHIVE.fflags=nodump" & Character'Val (10)
           & "25 LIBARCHIVE.note=hello" & Character'Val (10));
   begin
      Write_PAX_Header
        (Sink, Tarlib.Entries.PAX_Global_Header, Global, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "global PAX header");
      Write_PAX_Header
        (Sink, Tarlib.Entries.PAX_Extended_Header, Local, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "local PAX header");
      Tarlib.Internal.Headers.Build
        ("unknown.txt", Tarlib.Entries.Regular_File, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File),
         Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "file header");
      Tarlib.Test_Outputs.Write (Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write file");
      Tarlib.Test_Outputs.Write
        (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "first terminator");
      Tarlib.Test_Outputs.Write
        (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "second terminator");

      Tarlib.Test_Outputs.Rewind (Sink);
      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");
      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert (Result.Code = Tarlib.Errors.Success and then Has_Entry, "entry");
      Assert
        (Tarlib.Readers.Extended_Record_Count (Info) = 1,
         "unknown local PAX count");
      Assert
        (Tarlib.Readers.Extended_Key (Info, 1) = "LIBARCHIVE.note",
         "unknown key");
      Assert
        (Tarlib.Readers.Extended_Value (Info, 1) = "hello",
         "unknown value");
      Assert
        (Tarlib.Readers.XAttr_Count (Info) = 1, "xattr count");
      Assert
        (Tarlib.Readers.XAttr_Name (Info, 1) = "a", "xattr name");
      Assert
        (Tarlib.Readers.XAttr_Value (Info, 1) = "b", "xattr value");
      Assert
        (Tarlib.Readers.ACL_Access (Info) = "user::rw-", "access ACL");
      Assert
        (Tarlib.Readers.ACL_Default (Info) = "group::r--", "default ACL");
      Assert
        (Tarlib.Readers.File_Flags (Info) = "nodump", "file flags");
      Assert (Tarlib.Readers.Extended_Key (Info, 2) = "", "out of range key");
   end Test_Unknown_PAX_Records;

   procedure Test_PAX_Device_Number_Overrides
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
      Reader    : Tarlib.Readers.Reader;
      Info      : Tarlib.Readers.Entry_Info;
      Result    : Tarlib.Errors.Status;
      Has_Entry : Boolean;
      Header    : Ada.Streams.Stream_Element_Array (1 .. 512);
      PAX_Data  : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes
          ("23 SCHILY.devmajor=123" & Character'Val (10)
           & "22 SCHILY.devminor=45" & Character'Val (10));
   begin
      Write_PAX_Header
        (Sink, Tarlib.Entries.PAX_Extended_Header, PAX_Data, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "PAX device header");
      Tarlib.Internal.Headers.Build
        ("dev/node", Tarlib.Entries.Character_Device, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Character_Device),
         "", Tarlib.Entries.No_Device, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "device header builds");
      Tarlib.Test_Outputs.Write (Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write device header");
      Tarlib.Test_Outputs.Write
        (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "first terminator");
      Tarlib.Test_Outputs.Write
        (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "second terminator");

      Tarlib.Test_Outputs.Rewind (Sink);
      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");
      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert
        (Result.Code = Tarlib.Errors.Success and then Has_Entry,
         "device entry");
      Assert
        (Tarlib.Readers.Kind (Info) = Tarlib.Entries.Character_Device,
         "device kind");
      Assert (Tarlib.Readers.Device (Info).Major = 123, "PAX device major");
      Assert (Tarlib.Readers.Device (Info).Minor = 45, "PAX device minor");
   end Test_PAX_Device_Number_Overrides;

   procedure Test_PAX_Standard_Device_Number_Overrides
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
      Reader    : Tarlib.Readers.Reader;
      Info      : Tarlib.Readers.Entry_Info;
      Result    : Tarlib.Errors.Status;
      Has_Entry : Boolean;
      Header    : Ada.Streams.Stream_Element_Array (1 .. 512);
      PAX_Data  : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes
          ("15 devmajor=12" & Character'Val (10)
           & "15 devminor=34" & Character'Val (10));
   begin
      Write_PAX_Header
        (Sink, Tarlib.Entries.PAX_Extended_Header, PAX_Data, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "PAX device header");
      Tarlib.Internal.Headers.Build
        ("dev/block", Tarlib.Entries.Block_Device, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Block_Device),
         "", Tarlib.Entries.No_Device, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "device header builds");
      Tarlib.Test_Outputs.Write (Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write device header");
      Tarlib.Test_Outputs.Write
        (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "first terminator");
      Tarlib.Test_Outputs.Write
        (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "second terminator");

      Tarlib.Test_Outputs.Rewind (Sink);
      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");
      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert
        (Result.Code = Tarlib.Errors.Success and then Has_Entry,
         "device entry");
      Assert
        (Tarlib.Readers.Kind (Info) = Tarlib.Entries.Block_Device,
         "device kind");
      Assert (Tarlib.Readers.Device (Info).Major = 12, "PAX device major");
      Assert (Tarlib.Readers.Device (Info).Minor = 34, "PAX device minor");
   end Test_PAX_Standard_Device_Number_Overrides;

   procedure Test_Invalid_PAX_Device_Number_Metadata
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      procedure Check
        (Sink          : in out Tarlib.Test_Outputs.Memory_Sink;
         Expected_Code : Tarlib.Errors.Status_Code;
         Message       : String)
      is
         Reader    : Tarlib.Readers.Reader;
         Info      : Tarlib.Readers.Entry_Info;
         Result    : Tarlib.Errors.Status;
         Has_Entry : Boolean;
      begin
         Tarlib.Test_Outputs.Rewind (Sink);
         Tarlib.Readers.Initialize (Reader, Sink, Result);
         Assert (Result.Code = Tarlib.Errors.Success, Message & " initialize");
         Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
         Assert (Result.Code = Expected_Code, Message & " rejected");
         Assert
           (Tarlib.Readers.State (Reader) = Tarlib.Readers.Failed,
            Message & " failed state");
      end Check;

      Non_Device_Sink : aliased Tarlib.Test_Outputs.Memory_Sink;
      Overflow_Sink   : aliased Tarlib.Test_Outputs.Memory_Sink;
      Result          : Tarlib.Errors.Status;
      Header          : Ada.Streams.Stream_Element_Array (1 .. 512);
      Non_Device_PAX  : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes
          ("21 SCHILY.devmajor=7" & Character'Val (10));
      Overflow_PAX    : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes
          ("27 SCHILY.devmajor=2097152" & Character'Val (10));
   begin
      Write_PAX_Header
        (Non_Device_Sink, Tarlib.Entries.PAX_Extended_Header, Non_Device_PAX,
         Result);
      Assert (Result.Code = Tarlib.Errors.Success, "non-device PAX header");
      Tarlib.Internal.Headers.Build
        ("file.txt", Tarlib.Entries.Regular_File, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File),
         Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "file header");
      Tarlib.Test_Outputs.Write (Non_Device_Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write file header");
      Check
        (Non_Device_Sink, Tarlib.Errors.Invalid_Entry_Kind,
         "PAX device number for regular file");

      Write_PAX_Header
        (Overflow_Sink, Tarlib.Entries.PAX_Extended_Header, Overflow_PAX,
         Result);
      Assert (Result.Code = Tarlib.Errors.Success, "overflow PAX header");
      Check
        (Overflow_Sink, Tarlib.Errors.Invalid_Metadata,
         "PAX device number overflow");
   end Test_Invalid_PAX_Device_Number_Metadata;

   procedure Test_Writer_PAX_Metadata_Roundtrip
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
      Writer    : Tarlib.Writers.Writer;
      Reader    : Tarlib.Readers.Reader;
      Info      : Tarlib.Readers.Entry_Info;
      Result    : Tarlib.Errors.Status;
      Has_Entry : Boolean;
      Metadata  : Tarlib.Entries.Metadata :=
        Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File);
      Meta      : Tarlib.Entries.Metadata;
   begin
      Metadata.MTime :=
        Tarlib.Entries.Timestamp (Tarlib.USTAR_Timestamp_Max) + 1;
      Metadata.UID := Tarlib.Entries.Owner_Id (Tarlib.USTAR_Owner_Max + 1);
      Metadata.GID := Tarlib.Entries.Owner_Id (Tarlib.USTAR_Owner_Max + 2);

      Tarlib.Writers.Initialize (Writer, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "writer initialize");
      Tarlib.Writers.Begin_Entry
        (Writer, "metadata.txt", Tarlib.Entries.Regular_File, 0, Metadata,
         Result);
      Assert (Result.Code = Tarlib.Errors.Success, "begin metadata file");
      Tarlib.Writers.End_Entry (Writer, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "end metadata file");
      Tarlib.Writers.Finish (Writer, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "finish metadata archive");

      Tarlib.Test_Outputs.Rewind (Sink);
      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");
      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert
        (Result.Code = Tarlib.Errors.Success and then Has_Entry,
         "metadata entry");
      Assert (Tarlib.Readers.Path (Info) = "metadata.txt", "entry path");
      Meta := Tarlib.Readers.Metadata (Info);
      Assert (Meta.MTime = Metadata.MTime, "PAX mtime roundtrip");
      Assert (Meta.UID = Metadata.UID, "PAX uid roundtrip");
      Assert (Meta.GID = Metadata.GID, "PAX gid roundtrip");
   end Test_Writer_PAX_Metadata_Roundtrip;

   procedure Test_PAX_Fractional_MTime
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
      Reader    : Tarlib.Readers.Reader;
      Info      : Tarlib.Readers.Entry_Info;
      Result    : Tarlib.Errors.Status;
      Has_Entry : Boolean;
      Header    : Ada.Streams.Stream_Element_Array (1 .. 512);
      PAX_Data  : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes
          ("18 mtime=1234.987" & Character'Val (10));
      Meta      : Tarlib.Entries.Metadata;
   begin
      Write_PAX_Header
        (Sink, Tarlib.Entries.PAX_Extended_Header, PAX_Data, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "PAX mtime header");
      Tarlib.Internal.Headers.Build
        ("fractional.txt", Tarlib.Entries.Regular_File, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File),
         Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "file header");
      Tarlib.Test_Outputs.Write (Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write file header");
      Tarlib.Test_Outputs.Write
        (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "first terminator");
      Tarlib.Test_Outputs.Write
        (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "second terminator");

      Tarlib.Test_Outputs.Rewind (Sink);
      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");
      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert (Result.Code = Tarlib.Errors.Success and then Has_Entry, "entry");
      Meta := Tarlib.Readers.Metadata (Info);
      Assert (Meta.MTime = 1234, "fractional mtime truncates");
   end Test_PAX_Fractional_MTime;

   procedure Test_PAX_Negative_Timestamps
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
      Reader    : Tarlib.Readers.Reader;
      Info      : Tarlib.Readers.Entry_Info;
      Result    : Tarlib.Errors.Status;
      Has_Entry : Boolean;
      Header    : Ada.Streams.Stream_Element_Array (1 .. 512);
      Meta      : Tarlib.Entries.Metadata;
      PAX_Data  : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes
          ("16 mtime=-123.9" & Character'Val (10)
           & "12 atime=-5" & Character'Val (10)
           & "12 ctime=-6" & Character'Val (10));
   begin
      Write_PAX_Header
        (Sink, Tarlib.Entries.PAX_Extended_Header, PAX_Data, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "negative time PAX");
      Tarlib.Internal.Headers.Build
        ("negative.txt", Tarlib.Entries.Regular_File, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File),
         Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "file header");
      Tarlib.Test_Outputs.Write (Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write file");
      Tarlib.Test_Outputs.Write
        (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "first terminator");
      Tarlib.Test_Outputs.Write
        (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "second terminator");

      Tarlib.Test_Outputs.Rewind (Sink);
      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");
      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert (Result.Code = Tarlib.Errors.Success and then Has_Entry, "entry");
      Meta := Tarlib.Readers.Metadata (Info);
      Assert (Meta.MTime = -123, "negative mtime truncates");
      Assert (Meta.ATime = -5, "negative atime");
      Assert (Meta.CTime = -6, "negative ctime");
   end Test_PAX_Negative_Timestamps;

   procedure Test_Invalid_PAX_Fractional_MTime
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
      Reader    : Tarlib.Readers.Reader;
      Info      : Tarlib.Readers.Entry_Info;
      Result    : Tarlib.Errors.Status;
      Has_Entry : Boolean;
      Header    : Ada.Streams.Stream_Element_Array (1 .. 512);
      PAX_Data  : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes
          ("15 mtime=1234." & Character'Val (10));
   begin
      Write_PAX_Header
        (Sink, Tarlib.Entries.PAX_Extended_Header, PAX_Data, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "PAX mtime header");
      Tarlib.Internal.Headers.Build
        ("invalid.txt", Tarlib.Entries.Regular_File, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File),
         Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "file header");
      Tarlib.Test_Outputs.Write (Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write file header");

      Tarlib.Test_Outputs.Rewind (Sink);
      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");
      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert
        (Result.Code = Tarlib.Errors.Invalid_Archive,
         "trailing decimal point rejected");
   end Test_Invalid_PAX_Fractional_MTime;

   procedure Test_PAX_Numeric_Overflow
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
      Reader    : Tarlib.Readers.Reader;
      Info      : Tarlib.Readers.Entry_Info;
      Result    : Tarlib.Errors.Status;
      Has_Entry : Boolean;
      Header    : Ada.Streams.Stream_Element_Array (1 .. 512);
      PAX_Data  : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes
          ("30 size=184467440737095516160" & Character'Val (10));
   begin
      Write_PAX_Header
        (Sink, Tarlib.Entries.PAX_Extended_Header, PAX_Data, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "PAX size header");
      Tarlib.Internal.Headers.Build
        ("overflow.txt", Tarlib.Entries.Regular_File, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File),
         Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "file header");
      Tarlib.Test_Outputs.Write (Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write file header");

      Tarlib.Test_Outputs.Rewind (Sink);
      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");
      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert
        (Result.Code = Tarlib.Errors.Invalid_Archive,
         "PAX numeric overflow rejected");
   end Test_PAX_Numeric_Overflow;

   procedure Test_PAX_Signed_Positive_Numerics
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      procedure Check_Negative_Rejected is
         Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
         Reader    : Tarlib.Readers.Reader;
         Info      : Tarlib.Readers.Entry_Info;
         Result    : Tarlib.Errors.Status;
         Has_Entry : Boolean;
         Header    : Ada.Streams.Stream_Element_Array (1 .. 512);
         PAX_Data  : constant Ada.Streams.Stream_Element_Array :=
           Tarlib.Test_Fixtures.To_Bytes
             ("11 size=-1" & Character'Val (10));
      begin
         Write_PAX_Header
           (Sink, Tarlib.Entries.PAX_Extended_Header, PAX_Data, Result);
         Assert (Result.Code = Tarlib.Errors.Success, "negative PAX header");
         Tarlib.Internal.Headers.Build
           ("negative.txt", Tarlib.Entries.Regular_File, 0,
            Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File),
            Header, Result);
         Assert (Result.Code = Tarlib.Errors.Success, "negative file header");
         Tarlib.Test_Outputs.Write (Sink, Header, Result);
         Assert (Result.Code = Tarlib.Errors.Success, "write negative file");

         Tarlib.Test_Outputs.Rewind (Sink);
         Tarlib.Readers.Initialize (Reader, Sink, Result);
         Assert (Result.Code = Tarlib.Errors.Success, "negative initialize");
         Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
         Assert
           (Result.Code = Tarlib.Errors.Invalid_Archive,
            "negative PAX numeric rejected");
      end Check_Negative_Rejected;

      Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
      Reader    : Tarlib.Readers.Reader;
      Info      : Tarlib.Readers.Entry_Info;
      Result    : Tarlib.Errors.Status;
      Has_Entry : Boolean;
      Header    : Ada.Streams.Stream_Element_Array (1 .. 512);
      Meta      : Tarlib.Entries.Metadata;
      PAX_Data  : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes
          ("11 size=+5" & Character'Val (10)
           & "16 mtime=+123.5" & Character'Val (10)
           & "11 uid=+42" & Character'Val (10)
           & "11 gid=+77" & Character'Val (10));
   begin
      Write_PAX_Header
        (Sink, Tarlib.Entries.PAX_Extended_Header, PAX_Data, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "PAX plus header");
      Tarlib.Internal.Headers.Build
        ("plus.txt", Tarlib.Entries.Regular_File, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File),
         Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "file header");
      Tarlib.Test_Outputs.Write (Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write file header");

      Tarlib.Test_Outputs.Rewind (Sink);
      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");
      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert (Result.Code = Tarlib.Errors.Success and then Has_Entry, "entry");
      Assert (Tarlib.Readers.Size (Info) = 5, "signed-positive PAX size");
      Meta := Tarlib.Readers.Metadata (Info);
      Assert (Meta.MTime = 123, "signed-positive PAX mtime");
      Assert (Meta.UID = 42, "signed-positive PAX uid");
      Assert (Meta.GID = 77, "signed-positive PAX gid");

      Check_Negative_Rejected;
   end Test_PAX_Signed_Positive_Numerics;

   procedure Test_PAX_Record_Length_Overflow
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
      Reader    : Tarlib.Readers.Reader;
      Info      : Tarlib.Readers.Entry_Info;
      Result    : Tarlib.Errors.Status;
      Has_Entry : Boolean;
      Header    : Ada.Streams.Stream_Element_Array (1 .. 512);
      PAX_Data  : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes
          ("999999999999999999999999999999 path=bad"
           & Character'Val (10));
   begin
      Write_PAX_Header
        (Sink, Tarlib.Entries.PAX_Extended_Header, PAX_Data, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "PAX header");
      Tarlib.Internal.Headers.Build
        ("file.txt", Tarlib.Entries.Regular_File, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File),
         Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "file header");
      Tarlib.Test_Outputs.Write (Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write file");

      Tarlib.Test_Outputs.Rewind (Sink);
      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");
      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert
        (Result.Code = Tarlib.Errors.Invalid_Archive,
         "PAX record length overflow rejected");
      Assert
        (Tarlib.Readers.State (Reader) = Tarlib.Readers.Failed,
         "failed state");
   end Test_PAX_Record_Length_Overflow;

   procedure Test_Empty_PAX_Keyword_Rejected
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
      Reader    : Tarlib.Readers.Reader;
      Info      : Tarlib.Readers.Entry_Info;
      Result    : Tarlib.Errors.Status;
      Has_Entry : Boolean;
      Header    : Ada.Streams.Stream_Element_Array (1 .. 512);
      PAX_Data  : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes ("4 =" & Character'Val (10));
   begin
      Write_PAX_Header
        (Sink, Tarlib.Entries.PAX_Extended_Header, PAX_Data, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "PAX header");
      Tarlib.Internal.Headers.Build
        ("file.txt", Tarlib.Entries.Regular_File, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File),
         Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "file header");
      Tarlib.Test_Outputs.Write (Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write file");

      Tarlib.Test_Outputs.Rewind (Sink);
      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");
      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert
        (Result.Code = Tarlib.Errors.Invalid_Archive,
         "empty PAX keyword rejected");
      Assert
        (Tarlib.Readers.State (Reader) = Tarlib.Readers.Failed,
         "failed state");
   end Test_Empty_PAX_Keyword_Rejected;

   procedure Test_Empty_PAX_Path_Metadata_Rejected
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      procedure Check
        (PAX_Data : Ada.Streams.Stream_Element_Array;
         Message  : String)
      is
         Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
         Reader    : Tarlib.Readers.Reader;
         Info      : Tarlib.Readers.Entry_Info;
         Result    : Tarlib.Errors.Status;
         Has_Entry : Boolean;
         Header    : Ada.Streams.Stream_Element_Array (1 .. 512);
      begin
         Write_PAX_Header
           (Sink, Tarlib.Entries.PAX_Extended_Header, PAX_Data, Result);
         Assert (Result.Code = Tarlib.Errors.Success, Message & " header");
         Tarlib.Internal.Headers.Build
           ("file.txt", Tarlib.Entries.Regular_File, 0,
            Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File),
            Header, Result);
         Assert (Result.Code = Tarlib.Errors.Success, Message & " file header");
         Tarlib.Test_Outputs.Write (Sink, Header, Result);
         Assert (Result.Code = Tarlib.Errors.Success, Message & " write file");

         Tarlib.Test_Outputs.Rewind (Sink);
         Tarlib.Readers.Initialize (Reader, Sink, Result);
         Assert (Result.Code = Tarlib.Errors.Success, Message & " initialize");
         Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
         Assert
           (Result.Code = Tarlib.Errors.Invalid_Archive,
            Message & " rejected");
         Assert
           (Tarlib.Readers.State (Reader) = Tarlib.Readers.Failed,
            Message & " failed state");
      end Check;
   begin
      Check
        (Tarlib.Test_Fixtures.To_Bytes
           ("8 path=" & Character'Val (10)),
         "empty PAX path");
      Check
        (Tarlib.Test_Fixtures.To_Bytes
           ("13 linkpath=" & Character'Val (10)),
         "empty PAX linkpath");
   end Test_Empty_PAX_Path_Metadata_Rejected;

   procedure Test_Invalid_PAX_Path_Metadata_Rejected
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      procedure Check
        (PAX_Data : Ada.Streams.Stream_Element_Array;
         Message  : String)
      is
         Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
         Reader    : Tarlib.Readers.Reader;
         Info      : Tarlib.Readers.Entry_Info;
         Result    : Tarlib.Errors.Status;
         Has_Entry : Boolean;
         Header    : Ada.Streams.Stream_Element_Array (1 .. 512);
      begin
         Write_PAX_Header
           (Sink, Tarlib.Entries.PAX_Extended_Header, PAX_Data, Result);
         Assert (Result.Code = Tarlib.Errors.Success, Message & " header");
         Tarlib.Internal.Headers.Build
           ("file.txt", Tarlib.Entries.Regular_File, 0,
            Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File),
            Header, Result);
         Assert (Result.Code = Tarlib.Errors.Success, Message & " file header");
         Tarlib.Test_Outputs.Write (Sink, Header, Result);
         Assert (Result.Code = Tarlib.Errors.Success, Message & " write file");

         Tarlib.Test_Outputs.Rewind (Sink);
         Tarlib.Readers.Initialize (Reader, Sink, Result);
         Assert (Result.Code = Tarlib.Errors.Success, Message & " initialize");
         Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
         Assert
           (Result.Code = Tarlib.Errors.Invalid_Path,
            Message & " rejected");
         Assert
           (Tarlib.Readers.State (Reader) = Tarlib.Readers.Failed,
            Message & " failed state");
      end Check;
   begin
      Check
        (Tarlib.Test_Fixtures.To_Bytes
           ("13 path=/abs" & Character'Val (10)),
         "absolute PAX path");
      Check
        (Tarlib.Test_Fixtures.To_Bytes
           ("15 path=../bad" & Character'Val (10)),
         "parent PAX path");
   end Test_Invalid_PAX_Path_Metadata_Rejected;

   procedure Test_PAX_Link_Path_Kind_Validation
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      procedure Check_Hard_Link
        (PAX_Data : Ada.Streams.Stream_Element_Array;
         Message  : String)
      is
         Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
         Reader    : Tarlib.Readers.Reader;
         Info      : Tarlib.Readers.Entry_Info;
         Result    : Tarlib.Errors.Status;
         Has_Entry : Boolean;
         Header    : Ada.Streams.Stream_Element_Array (1 .. 512);
      begin
         Write_PAX_Header
           (Sink, Tarlib.Entries.PAX_Extended_Header, PAX_Data, Result);
         Assert (Result.Code = Tarlib.Errors.Success, Message & " header");
         Tarlib.Internal.Headers.Build
           ("alias", Tarlib.Entries.Hard_Link, 0,
            Tarlib.Entries.Default_Metadata (Tarlib.Entries.Hard_Link),
            "placeholder", Header, Result);
         Assert
           (Result.Code = Tarlib.Errors.Success, Message & " hard link header");
         Tarlib.Test_Outputs.Write (Sink, Header, Result);
         Assert (Result.Code = Tarlib.Errors.Success, Message & " write link");

         Tarlib.Test_Outputs.Rewind (Sink);
         Tarlib.Readers.Initialize (Reader, Sink, Result);
         Assert (Result.Code = Tarlib.Errors.Success, Message & " initialize");
         Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
         Assert
           (Result.Code = Tarlib.Errors.Invalid_Path,
            Message & " rejected");
         Assert
           (Tarlib.Readers.State (Reader) = Tarlib.Readers.Failed,
            Message & " failed state");
      end Check_Hard_Link;

      Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
      Reader    : Tarlib.Readers.Reader;
      Info      : Tarlib.Readers.Entry_Info;
      Result    : Tarlib.Errors.Status;
      Has_Entry : Boolean;
      Header    : Ada.Streams.Stream_Element_Array (1 .. 512);
      Symlink_PAX : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes
          ("17 linkpath=/abs" & Character'Val (10));
   begin
      Check_Hard_Link
        (Tarlib.Test_Fixtures.To_Bytes
           ("17 linkpath=/abs" & Character'Val (10)),
         "absolute hard-link PAX linkpath");
      Check_Hard_Link
        (Tarlib.Test_Fixtures.To_Bytes
           ("19 linkpath=../bad" & Character'Val (10)),
         "parent hard-link PAX linkpath");

      Write_PAX_Header
        (Sink, Tarlib.Entries.PAX_Extended_Header, Symlink_PAX, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "symlink PAX header");
      Tarlib.Internal.Headers.Build
        ("symlink", Tarlib.Entries.Symbolic_Link, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Symbolic_Link),
         "placeholder", Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "symlink header");
      Tarlib.Test_Outputs.Write (Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write symlink");

      Tarlib.Test_Outputs.Rewind (Sink);
      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");
      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert
        (Result.Code = Tarlib.Errors.Success and then Has_Entry,
         "symlink entry");
      Assert
        (Tarlib.Readers.Link_Path (Info) = "/abs",
         "absolute symlink target preserved");
   end Test_PAX_Link_Path_Kind_Validation;

   procedure Test_Raw_Hard_Link_Target_Validation
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      procedure Check
        (Target  : String;
         Message : String)
      is
         Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
         Reader    : Tarlib.Readers.Reader;
         Info      : Tarlib.Readers.Entry_Info;
         Result    : Tarlib.Errors.Status;
         Has_Entry : Boolean;
         Header    : Ada.Streams.Stream_Element_Array (1 .. 512);
      begin
         Tarlib.Internal.Headers.Build
           ("alias", Tarlib.Entries.Hard_Link, 0,
            Tarlib.Entries.Default_Metadata (Tarlib.Entries.Hard_Link),
            Target, Header, Result);
         Assert (Result.Code = Tarlib.Errors.Success, Message & " header");
         Tarlib.Test_Outputs.Write (Sink, Header, Result);
         Assert (Result.Code = Tarlib.Errors.Success, Message & " write");

         Tarlib.Test_Outputs.Rewind (Sink);
         Tarlib.Readers.Initialize (Reader, Sink, Result);
         Assert (Result.Code = Tarlib.Errors.Success, Message & " initialize");
         Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
         Assert
           (Result.Code = Tarlib.Errors.Invalid_Path,
            Message & " rejected");
         Assert
           (Tarlib.Readers.State (Reader) = Tarlib.Readers.Failed,
            Message & " failed state");
      end Check;

      procedure Check_Valid
        (Target  : String;
         Message : String)
      is
         Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
         Reader    : Tarlib.Readers.Reader;
         Info      : Tarlib.Readers.Entry_Info;
         Result    : Tarlib.Errors.Status;
         Has_Entry : Boolean;
         Header    : Ada.Streams.Stream_Element_Array (1 .. 512);
      begin
         Tarlib.Internal.Headers.Build
           ("alias", Tarlib.Entries.Hard_Link, 0,
            Tarlib.Entries.Default_Metadata (Tarlib.Entries.Hard_Link),
            Target, Header, Result);
         Assert (Result.Code = Tarlib.Errors.Success, Message & " header");
         Tarlib.Test_Outputs.Write (Sink, Header, Result);
         Assert (Result.Code = Tarlib.Errors.Success, Message & " write");
         Tarlib.Test_Outputs.Write
           (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
         Assert (Result.Code = Tarlib.Errors.Success, Message & " terminator");

         Tarlib.Test_Outputs.Rewind (Sink);
         Tarlib.Readers.Initialize (Reader, Sink, Result);
         Assert (Result.Code = Tarlib.Errors.Success, Message & " initialize");
         Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
         Assert
           (Result.Code = Tarlib.Errors.Success and then Has_Entry,
            Message & " accepted");
         Assert
           (Tarlib.Readers.Kind (Info) = Tarlib.Entries.Hard_Link,
            Message & " kind");
         Assert (Tarlib.Readers.Path (Info) = "alias", Message & " path");
         Assert
           (Tarlib.Readers.Link_Path (Info) = Target,
            Message & " target");
      end Check_Valid;
   begin
      Check_Valid ("target/file.txt", "raw relative hard-link target");
      Check ("/abs", "raw absolute hard-link target");
      Check ("../bad", "raw parent hard-link target");
   end Test_Raw_Hard_Link_Target_Validation;

   procedure Test_PAX_Link_Path_Supplies_Empty_Header_Target
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      procedure Write_Link_Header
        (Sink   : in out Tarlib.Test_Outputs.Memory_Sink;
         Kind   : Tarlib.Entries.Entry_Kind;
         Result : out Tarlib.Errors.Status)
      is
         Header : Ada.Streams.Stream_Element_Array (1 .. 512);
      begin
         Tarlib.Internal.Headers.Build
           ("link", Tarlib.Entries.Regular_File, 0,
            Tarlib.Entries.Default_Metadata (Kind), Header, Result);
         if Result.Code /= Tarlib.Errors.Success then
            return;
         end if;

         Header (149 .. 156) := [others => 32];
         Header (157) :=
           (if Kind = Tarlib.Entries.Hard_Link
            then Character'Pos ('1')
            else Character'Pos ('2'));
         Tarlib.Internal.Fields.Put_Octal
           (Header (149 .. 156),
            Tarlib.Internal.Checksums.Compute (Header),
            Tarlib.Internal.Fields.Checksum_Terminated, Result);
         if Result.Code = Tarlib.Errors.Success then
            Tarlib.Test_Outputs.Write (Sink, Header, Result);
         end if;
      end Write_Link_Header;

      Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
      Missing   : aliased Tarlib.Test_Outputs.Memory_Sink;
      Reader    : Tarlib.Readers.Reader;
      Missing_Reader : Tarlib.Readers.Reader;
      Info      : Tarlib.Readers.Entry_Info;
      Result    : Tarlib.Errors.Status;
      Has_Entry : Boolean;
      PAX_Data  : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes
          ("19 linkpath=target" & Character'Val (10));
   begin
      Write_PAX_Header
        (Sink, Tarlib.Entries.PAX_Extended_Header, PAX_Data, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "PAX linkpath header");
      Write_Link_Header (Sink, Tarlib.Entries.Hard_Link, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "empty hard link header");

      Tarlib.Test_Outputs.Rewind (Sink);
      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");
      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert (Result.Code = Tarlib.Errors.Success and then Has_Entry, "entry");
      Assert
        (Tarlib.Readers.Kind (Info) = Tarlib.Entries.Hard_Link,
         "hard link kind");
      Assert (Tarlib.Readers.Link_Path (Info) = "target", "PAX linkpath");

      Write_Link_Header (Missing, Tarlib.Entries.Symbolic_Link, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "empty symlink header");
      Tarlib.Test_Outputs.Rewind (Missing);
      Tarlib.Readers.Initialize (Missing_Reader, Missing, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "missing initialize");
      Tarlib.Readers.Next_Entry (Missing_Reader, Info, Has_Entry, Result);
      Assert
        (Result.Code = Tarlib.Errors.Invalid_Metadata,
         "empty link target without PAX rejected");
      Assert
        (Tarlib.Readers.State (Missing_Reader) = Tarlib.Readers.Failed,
         "missing target failed state");
   end Test_PAX_Link_Path_Supplies_Empty_Header_Target;

   procedure Test_PAX_Size_Ignored_For_Non_File
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
      Reader    : Tarlib.Readers.Reader;
      Info      : Tarlib.Readers.Entry_Info;
      Result    : Tarlib.Errors.Status;
      Has_Entry : Boolean;
      Header    : Ada.Streams.Stream_Element_Array (1 .. 512);
      PAX_Data  : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes
          ("9 size=3" & Character'Val (10));
   begin
      Write_PAX_Header
        (Sink, Tarlib.Entries.PAX_Extended_Header, PAX_Data, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "PAX size header");
      Tarlib.Internal.Headers.Build
        ("dir/", Tarlib.Entries.Directory, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Directory),
         Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "directory header");
      Tarlib.Test_Outputs.Write (Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write directory header");

      Write_PAX_Header
        (Sink, Tarlib.Entries.PAX_Extended_Header, PAX_Data, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "symlink PAX size header");
      Tarlib.Internal.Headers.Build
        ("link", Tarlib.Entries.Symbolic_Link, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Symbolic_Link),
         "target", Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "symlink header");
      Tarlib.Test_Outputs.Write (Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write symlink header");

      Write_PAX_Header
        (Sink, Tarlib.Entries.PAX_Extended_Header, PAX_Data, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "device PAX size header");
      Tarlib.Internal.Headers.Build
        ("dev/null", Tarlib.Entries.Character_Device, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Character_Device),
         "", (Major => 1, Minor => 3), Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "device header");
      Tarlib.Test_Outputs.Write (Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write device header");

      Write_PAX_Header
        (Sink, Tarlib.Entries.PAX_Extended_Header, PAX_Data, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "FIFO PAX size header");
      Tarlib.Internal.Headers.Build
        ("pipe", Tarlib.Entries.FIFO, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.FIFO),
         Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "FIFO header");
      Tarlib.Test_Outputs.Write (Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write FIFO header");

      Tarlib.Test_Outputs.Write
        (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "first terminator");
      Tarlib.Test_Outputs.Write
        (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "second terminator");

      Tarlib.Test_Outputs.Rewind (Sink);
      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");
      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert
        (Result.Code = Tarlib.Errors.Success and then Has_Entry,
         "directory entry");
      Assert (Tarlib.Readers.Size (Info) = 0, "directory size stays zero");

      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert
        (Result.Code = Tarlib.Errors.Success and then Has_Entry,
         "symlink entry");
      Assert (Tarlib.Readers.Size (Info) = 0, "symlink size stays zero");
      Assert (Tarlib.Readers.Link_Path (Info) = "target", "symlink target");

      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert
        (Result.Code = Tarlib.Errors.Success and then Has_Entry,
         "device entry");
      Assert (Tarlib.Readers.Size (Info) = 0, "device size stays zero");
      Assert (Tarlib.Readers.Device (Info).Major = 1, "device major");

      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert
        (Result.Code = Tarlib.Errors.Success and then Has_Entry,
         "FIFO entry");
      Assert (Tarlib.Readers.Size (Info) = 0, "FIFO size stays zero");

      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "terminator after entries");
      Assert (not Has_Entry, "no more entries");
      Assert (Tarlib.Readers.At_End (Reader), "reader at end");
   end Test_PAX_Size_Ignored_For_Non_File;

   procedure Write_Header_Entry
     (Sink   : in out Tarlib.Test_Outputs.Memory_Sink;
      Kind   : Tarlib.Entries.Entry_Kind;
      Size   : Tarlib.Byte_Count;
      Result : out Tarlib.Errors.Status)
   is
      Header : Ada.Streams.Stream_Element_Array (1 .. 512);
   begin
      Tarlib.Internal.Headers.Build
        ("././@LongLink", Kind, Size,
         Tarlib.Entries.Default_Metadata (Kind), Header, Result);
      if Result.Code = Tarlib.Errors.Success then
         Tarlib.Test_Outputs.Write (Sink, Header, Result);
      end if;
   end Write_Header_Entry;

   procedure Write_Padded_Data
     (Sink   : in out Tarlib.Test_Outputs.Memory_Sink;
      Data   : Ada.Streams.Stream_Element_Array;
      Result : out Tarlib.Errors.Status);

   procedure Write_PAX_Header
     (Sink   : in out Tarlib.Test_Outputs.Memory_Sink;
      Kind   : Tarlib.Entries.Entry_Kind;
      Data   : Ada.Streams.Stream_Element_Array;
      Result : out Tarlib.Errors.Status)
   is
      Header : Ada.Streams.Stream_Element_Array (1 .. 512);
   begin
      Tarlib.Internal.Headers.Build
        ("PaxHeaders/metadata", Kind, Tarlib.Byte_Count (Data'Length),
         Tarlib.Entries.Default_Metadata (Kind), Header, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Tarlib.Test_Outputs.Write (Sink, Header, Result);
      if Result.Code = Tarlib.Errors.Success then
         Write_Padded_Data (Sink, Data, Result);
      end if;
   end Write_PAX_Header;

   procedure Write_Padded_Data
     (Sink   : in out Tarlib.Test_Outputs.Memory_Sink;
      Data   : Ada.Streams.Stream_Element_Array;
      Result : out Tarlib.Errors.Status)
   is
      Padding : constant Ada.Streams.Stream_Element_Offset :=
        512 - Ada.Streams.Stream_Element_Offset (Data'Length);
   begin
      Tarlib.Test_Outputs.Write (Sink, Data, Result);
      if Result.Code = Tarlib.Errors.Success and then Padding > 0 then
         Tarlib.Test_Outputs.Write (Sink, [1 .. Padding => 0], Result);
      end if;
   end Write_Padded_Data;

   procedure Test_GNU_Long_Name_And_Link
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
      Reader    : Tarlib.Readers.Reader;
      Info      : Tarlib.Readers.Entry_Info;
      Result    : Tarlib.Errors.Status;
      Has_Entry : Boolean;
      Header    : Ada.Streams.Stream_Element_Array (1 .. 512);
      Long_Path : constant String :=
        "gnu/" & Repeat ('k', 120) & "/" & Repeat ('l', 120) & "/file.txt";
      Long_Link : constant String :=
        "gnu-targets/" & Repeat ('m', 120) & "/" & Repeat ('n', 120);
      Name_Data : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes (Long_Path & Character'Val (0));
      Link_Data : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes (Long_Link & Character'Val (0));
   begin
      Write_Header_Entry
        (Sink, Tarlib.Entries.GNU_Long_Name,
         Tarlib.Byte_Count (Name_Data'Length), Result);
      Assert (Result.Code = Tarlib.Errors.Success, "GNU long name header");
      Write_Padded_Data (Sink, Name_Data, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "GNU long name data");
      Tarlib.Internal.Headers.Build
        ("placeholder", Tarlib.Entries.Regular_File, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File),
         Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "file header");
      Tarlib.Test_Outputs.Write (Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write file header");

      Write_Header_Entry
        (Sink, Tarlib.Entries.GNU_Long_Link,
         Tarlib.Byte_Count (Link_Data'Length), Result);
      Assert (Result.Code = Tarlib.Errors.Success, "GNU long link header");
      Write_Padded_Data (Sink, Link_Data, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "GNU long link data");
      Tarlib.Internal.Headers.Build
        ("symlink", Tarlib.Entries.Symbolic_Link, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Symbolic_Link),
         "placeholder", Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "symlink header");
      Tarlib.Test_Outputs.Write (Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write symlink header");
      Tarlib.Test_Outputs.Write
        (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "first terminator");
      Tarlib.Test_Outputs.Write
        (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "second terminator");

      Tarlib.Test_Outputs.Rewind (Sink);
      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");
      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert (Result.Code = Tarlib.Errors.Success and then Has_Entry, "file");
      Assert (Tarlib.Readers.Path (Info) = Long_Path, "GNU long name");

      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert (Result.Code = Tarlib.Errors.Success and then Has_Entry, "link");
      Assert (Tarlib.Readers.Path (Info) = "symlink", "link path");
      Assert (Tarlib.Readers.Link_Path (Info) = Long_Link, "GNU long link");
   end Test_GNU_Long_Name_And_Link;

   procedure Test_Invalid_GNU_Long_Name_Rejected
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      procedure Check
        (Name_Data : Ada.Streams.Stream_Element_Array;
         Message   : String)
      is
         Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
         Reader    : Tarlib.Readers.Reader;
         Info      : Tarlib.Readers.Entry_Info;
         Result    : Tarlib.Errors.Status;
         Has_Entry : Boolean;
         Header    : Ada.Streams.Stream_Element_Array (1 .. 512);
      begin
         Write_Header_Entry
           (Sink, Tarlib.Entries.GNU_Long_Name,
            Tarlib.Byte_Count (Name_Data'Length), Result);
         Assert (Result.Code = Tarlib.Errors.Success, Message & " header");
         Write_Padded_Data (Sink, Name_Data, Result);
         Assert (Result.Code = Tarlib.Errors.Success, Message & " data");
         Tarlib.Internal.Headers.Build
           ("placeholder", Tarlib.Entries.Regular_File, 0,
            Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File),
            Header, Result);
         Assert (Result.Code = Tarlib.Errors.Success, Message & " file header");
         Tarlib.Test_Outputs.Write (Sink, Header, Result);
         Assert (Result.Code = Tarlib.Errors.Success, Message & " write file");

         Tarlib.Test_Outputs.Rewind (Sink);
         Tarlib.Readers.Initialize (Reader, Sink, Result);
         Assert (Result.Code = Tarlib.Errors.Success, Message & " initialize");
         Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
         Assert
           (Result.Code = Tarlib.Errors.Invalid_Path,
            Message & " rejected");
         Assert
           (Tarlib.Readers.State (Reader) = Tarlib.Readers.Failed,
            Message & " failed state");
      end Check;
   begin
      Check
        (Tarlib.Test_Fixtures.To_Bytes ("/abs/path" & Character'Val (0)),
         "absolute GNU long name");
      Check
        (Tarlib.Test_Fixtures.To_Bytes ("../bad" & Character'Val (0)),
         "parent GNU long name");
   end Test_Invalid_GNU_Long_Name_Rejected;

   procedure Test_GNU_Long_Link_Kind_Validation
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      procedure Check_Hard_Link
        (Link_Data : Ada.Streams.Stream_Element_Array;
         Message   : String)
      is
         Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
         Reader    : Tarlib.Readers.Reader;
         Info      : Tarlib.Readers.Entry_Info;
         Result    : Tarlib.Errors.Status;
         Has_Entry : Boolean;
         Header    : Ada.Streams.Stream_Element_Array (1 .. 512);
      begin
         Write_Header_Entry
           (Sink, Tarlib.Entries.GNU_Long_Link,
            Tarlib.Byte_Count (Link_Data'Length), Result);
         Assert (Result.Code = Tarlib.Errors.Success, Message & " header");
         Write_Padded_Data (Sink, Link_Data, Result);
         Assert (Result.Code = Tarlib.Errors.Success, Message & " data");
         Tarlib.Internal.Headers.Build
           ("alias", Tarlib.Entries.Hard_Link, 0,
            Tarlib.Entries.Default_Metadata (Tarlib.Entries.Hard_Link),
            "placeholder", Header, Result);
         Assert
           (Result.Code = Tarlib.Errors.Success, Message & " hard link header");
         Tarlib.Test_Outputs.Write (Sink, Header, Result);
         Assert (Result.Code = Tarlib.Errors.Success, Message & " write link");

         Tarlib.Test_Outputs.Rewind (Sink);
         Tarlib.Readers.Initialize (Reader, Sink, Result);
         Assert (Result.Code = Tarlib.Errors.Success, Message & " initialize");
         Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
         Assert
           (Result.Code = Tarlib.Errors.Invalid_Path,
            Message & " rejected");
         Assert
           (Tarlib.Readers.State (Reader) = Tarlib.Readers.Failed,
            Message & " failed state");
      end Check_Hard_Link;

      Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
      Reader    : Tarlib.Readers.Reader;
      Info      : Tarlib.Readers.Entry_Info;
      Result    : Tarlib.Errors.Status;
      Has_Entry : Boolean;
      Header    : Ada.Streams.Stream_Element_Array (1 .. 512);
      Symlink_Data : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes ("/abs" & Character'Val (0));
   begin
      Check_Hard_Link
        (Tarlib.Test_Fixtures.To_Bytes ("/abs" & Character'Val (0)),
         "absolute GNU long hard-link target");
      Check_Hard_Link
        (Tarlib.Test_Fixtures.To_Bytes ("../bad" & Character'Val (0)),
         "parent GNU long hard-link target");

      Write_Header_Entry
        (Sink, Tarlib.Entries.GNU_Long_Link,
         Tarlib.Byte_Count (Symlink_Data'Length), Result);
      Assert (Result.Code = Tarlib.Errors.Success, "symlink long link header");
      Write_Padded_Data (Sink, Symlink_Data, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "symlink long link data");
      Tarlib.Internal.Headers.Build
        ("symlink", Tarlib.Entries.Symbolic_Link, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Symbolic_Link),
         "placeholder", Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "symlink header");
      Tarlib.Test_Outputs.Write (Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write symlink");

      Tarlib.Test_Outputs.Rewind (Sink);
      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");
      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert
        (Result.Code = Tarlib.Errors.Success and then Has_Entry,
         "symlink entry");
      Assert
        (Tarlib.Readers.Link_Path (Info) = "/abs",
         "absolute GNU symlink target preserved");
   end Test_GNU_Long_Link_Kind_Validation;

   procedure Test_NUL_Link_Metadata_Rejected
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      procedure Check
        (Sink    : in out Tarlib.Test_Outputs.Memory_Sink;
         Message : String)
      is
         Reader    : Tarlib.Readers.Reader;
         Info      : Tarlib.Readers.Entry_Info;
         Result    : Tarlib.Errors.Status;
         Has_Entry : Boolean;
      begin
         Tarlib.Test_Outputs.Rewind (Sink);
         Tarlib.Readers.Initialize (Reader, Sink, Result);
         Assert (Result.Code = Tarlib.Errors.Success, Message & " initialize");
         Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
         Assert
           (Result.Code = Tarlib.Errors.Invalid_Archive,
            Message & " rejected");
         Assert
           (Tarlib.Readers.State (Reader) = Tarlib.Readers.Failed,
            Message & " failed state");
      end Check;

      PAX_Sink : aliased Tarlib.Test_Outputs.Memory_Sink;
      GNU_Sink : aliased Tarlib.Test_Outputs.Memory_Sink;
      Result   : Tarlib.Errors.Status;
      Header   : Ada.Streams.Stream_Element_Array (1 .. 512);
      PAX_Data : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes
          ("16 linkpath=a" & Character'Val (0) & "b" & Character'Val (10));
      GNU_Data : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes
          ("a" & Character'Val (0) & "b" & Character'Val (0));
   begin
      Write_PAX_Header
        (PAX_Sink, Tarlib.Entries.PAX_Extended_Header, PAX_Data, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "PAX linkpath header");
      Tarlib.Internal.Headers.Build
        ("symlink", Tarlib.Entries.Symbolic_Link, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Symbolic_Link),
         "placeholder", Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "PAX symlink header");
      Tarlib.Test_Outputs.Write (PAX_Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write PAX symlink");
      Check (PAX_Sink, "NUL PAX linkpath");

      Write_Header_Entry
        (GNU_Sink, Tarlib.Entries.GNU_Long_Link,
         Tarlib.Byte_Count (GNU_Data'Length), Result);
      Assert (Result.Code = Tarlib.Errors.Success, "GNU long link header");
      Write_Padded_Data (GNU_Sink, GNU_Data, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "GNU long link data");
      Tarlib.Internal.Headers.Build
        ("symlink", Tarlib.Entries.Symbolic_Link, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Symbolic_Link),
         "placeholder", Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "GNU symlink header");
      Tarlib.Test_Outputs.Write (GNU_Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write GNU symlink");
      Check (GNU_Sink, "NUL GNU long link");
   end Test_NUL_Link_Metadata_Rejected;

   procedure Test_Link_Metadata_For_Non_Link_Rejected
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      procedure Check
        (Sink    : in out Tarlib.Test_Outputs.Memory_Sink;
         Message : String)
      is
         Reader    : Tarlib.Readers.Reader;
         Info      : Tarlib.Readers.Entry_Info;
         Result    : Tarlib.Errors.Status;
         Has_Entry : Boolean;
      begin
         Tarlib.Test_Outputs.Rewind (Sink);
         Tarlib.Readers.Initialize (Reader, Sink, Result);
         Assert (Result.Code = Tarlib.Errors.Success, Message & " initialize");
         Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
         Assert
           (Result.Code = Tarlib.Errors.Invalid_Entry_Kind,
            Message & " rejected");
         Assert
           (Tarlib.Readers.State (Reader) = Tarlib.Readers.Failed,
            Message & " failed state");
      end Check;

      PAX_Sink : aliased Tarlib.Test_Outputs.Memory_Sink;
      GNU_Sink : aliased Tarlib.Test_Outputs.Memory_Sink;
      Result   : Tarlib.Errors.Status;
      Header   : Ada.Streams.Stream_Element_Array (1 .. 512);
      PAX_Data : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes
          ("19 linkpath=target" & Character'Val (10));
      GNU_Data : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes ("target" & Character'Val (0));
   begin
      Write_PAX_Header
        (PAX_Sink, Tarlib.Entries.PAX_Extended_Header, PAX_Data, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "PAX linkpath header");
      Tarlib.Internal.Headers.Build
        ("file.txt", Tarlib.Entries.Regular_File, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File),
         Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "PAX file header");
      Tarlib.Test_Outputs.Write (PAX_Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write PAX file");
      Check (PAX_Sink, "PAX linkpath for regular file");

      Write_Header_Entry
        (GNU_Sink, Tarlib.Entries.GNU_Long_Link,
         Tarlib.Byte_Count (GNU_Data'Length), Result);
      Assert (Result.Code = Tarlib.Errors.Success, "GNU long link header");
      Write_Padded_Data (GNU_Sink, GNU_Data, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "GNU long link data");
      Tarlib.Internal.Headers.Build
        ("file.txt", Tarlib.Entries.Regular_File, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File),
         Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "GNU file header");
      Tarlib.Test_Outputs.Write (GNU_Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write GNU file");
      Check (GNU_Sink, "GNU long link for regular file");
   end Test_Link_Metadata_For_Non_Link_Rejected;

   procedure Test_Global_PAX_Metadata
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
      Reader    : Tarlib.Readers.Reader;
      Info      : Tarlib.Readers.Entry_Info;
      Result    : Tarlib.Errors.Status;
      Has_Entry : Boolean;
      Header    : Ada.Streams.Stream_Element_Array (1 .. 512);
      Global    : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes
          ("13 mtime=555" & Character'Val (10)
           & "9 uid=11" & Character'Val (10)
           & "9 gid=22" & Character'Val (10));
      Local     : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes ("13 mtime=777" & Character'Val (10));
      Meta      : Tarlib.Entries.Metadata;
   begin
      Write_PAX_Header
        (Sink, Tarlib.Entries.PAX_Global_Header, Global, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "global PAX header");

      Tarlib.Internal.Headers.Build
        ("one.txt", Tarlib.Entries.Regular_File, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File),
         Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "first file header");
      Tarlib.Test_Outputs.Write (Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write first file");

      Write_PAX_Header
        (Sink, Tarlib.Entries.PAX_Extended_Header, Local, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "local PAX header");
      Tarlib.Internal.Headers.Build
        ("two.txt", Tarlib.Entries.Regular_File, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File),
         Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "second file header");
      Tarlib.Test_Outputs.Write (Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write second file");
      Tarlib.Test_Outputs.Write
        (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "first terminator");
      Tarlib.Test_Outputs.Write
        (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "second terminator");

      Tarlib.Test_Outputs.Rewind (Sink);
      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");
      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert (Result.Code = Tarlib.Errors.Success and then Has_Entry, "first");
      Meta := Tarlib.Readers.Metadata (Info);
      Assert (Meta.MTime = 555, "global mtime");
      Assert (Meta.UID = 11, "global uid");
      Assert (Meta.GID = 22, "global gid");

      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert (Result.Code = Tarlib.Errors.Success and then Has_Entry, "second");
      Meta := Tarlib.Readers.Metadata (Info);
      Assert (Meta.MTime = 777, "local mtime overrides global");
      Assert (Meta.UID = 11, "global uid persists");
      Assert (Meta.GID = 22, "global gid persists");
   end Test_Global_PAX_Metadata;

   procedure Test_PAX_Owner_Names
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
      Reader    : Tarlib.Readers.Reader;
      Info      : Tarlib.Readers.Entry_Info;
      Result    : Tarlib.Errors.Status;
      Has_Entry : Boolean;
      Header    : Ada.Streams.Stream_Element_Array (1 .. 512);
      Meta      : Tarlib.Entries.Metadata;
      Header_Meta : Tarlib.Entries.Metadata :=
        Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File);
      Global   : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes
          ("16 uname=global" & Character'Val (10)
           & "15 gname=wheel" & Character'Val (10));
      Local    : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes
          ("15 uname=local" & Character'Val (10)
           & "18 gname=builders" & Character'Val (10));
   begin
      Tarlib.Entries.Set_Text (Header_Meta.User_Name, "header", Result);
      Assert (Result.Code = Tarlib.Errors.Success, "header user set");
      Tarlib.Entries.Set_Text (Header_Meta.Group_Name, "users", Result);
      Assert (Result.Code = Tarlib.Errors.Success, "header group set");

      Write_PAX_Header
        (Sink, Tarlib.Entries.PAX_Global_Header, Global, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "global PAX header");
      Tarlib.Internal.Headers.Build
        ("first.txt", Tarlib.Entries.Regular_File, 0, Header_Meta,
         Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "first header");
      Tarlib.Test_Outputs.Write (Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write first");

      Write_PAX_Header
        (Sink, Tarlib.Entries.PAX_Extended_Header, Local, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "local PAX header");
      Tarlib.Internal.Headers.Build
        ("second.txt", Tarlib.Entries.Regular_File, 0, Header_Meta,
         Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "second header");
      Tarlib.Test_Outputs.Write (Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write second");
      Tarlib.Test_Outputs.Write
        (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "first terminator");
      Tarlib.Test_Outputs.Write
        (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "second terminator");

      Tarlib.Test_Outputs.Rewind (Sink);
      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");
      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert (Result.Code = Tarlib.Errors.Success and then Has_Entry, "first");
      Meta := Tarlib.Readers.Metadata (Info);
      Assert
        (Tarlib.Entries.Text (Meta.User_Name) = "global",
         "global user name");
      Assert
        (Tarlib.Entries.Text (Meta.Group_Name) = "wheel",
         "global group name");

      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert (Result.Code = Tarlib.Errors.Success and then Has_Entry, "second");
      Meta := Tarlib.Readers.Metadata (Info);
      Assert
        (Tarlib.Entries.Text (Meta.User_Name) = "local",
         "local user name");
      Assert
        (Tarlib.Entries.Text (Meta.Group_Name) = "builders",
         "local group name");
   end Test_PAX_Owner_Names;

   procedure Test_Global_PAX_Metadata_Delete
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
      Reader    : Tarlib.Readers.Reader;
      Info      : Tarlib.Readers.Entry_Info;
      Result    : Tarlib.Errors.Status;
      Has_Entry : Boolean;
      Header    : Ada.Streams.Stream_Element_Array (1 .. 512);
      Global    : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes
          ("13 mtime=555" & Character'Val (10)
           & "9 uid=11" & Character'Val (10)
           & "9 gid=22" & Character'Val (10));
      Clear     : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes
          ("9 mtime=" & Character'Val (10)
           & "7 uid=" & Character'Val (10)
           & "7 gid=" & Character'Val (10)
           & "12 size=bad" & Character'Val (10));
      Meta      : Tarlib.Entries.Metadata;
   begin
      Write_PAX_Header
        (Sink, Tarlib.Entries.PAX_Global_Header, Global, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "global PAX header");

      Tarlib.Internal.Headers.Build
        ("one.txt", Tarlib.Entries.Regular_File, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File),
         Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "first file header");
      Tarlib.Test_Outputs.Write (Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write first file");

      Write_PAX_Header
        (Sink, Tarlib.Entries.PAX_Global_Header, Clear, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "clear global PAX header");

      Tarlib.Internal.Headers.Build
        ("two.txt", Tarlib.Entries.Regular_File, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File),
         Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "second file header");
      Tarlib.Test_Outputs.Write (Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write second file");

      Tarlib.Test_Outputs.Rewind (Sink);
      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");
      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert (Result.Code = Tarlib.Errors.Success and then Has_Entry, "first");
      Meta := Tarlib.Readers.Metadata (Info);
      Assert (Meta.MTime = 555, "global mtime applies");
      Assert (Meta.UID = 11, "global uid applies");
      Assert (Meta.GID = 22, "global gid applies");

      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert (Result.Code = Tarlib.Errors.Success and then Has_Entry, "second");
      Assert (Tarlib.Readers.Size (Info) = 0, "malformed global size ignored");
      Meta := Tarlib.Readers.Metadata (Info);
      Assert
        (Meta.MTime = Tarlib.Entries.Default_Timestamp,
         "global mtime deleted");
      Assert (Meta.UID = Tarlib.Entries.Default_Owner, "global uid deleted");
      Assert (Meta.GID = Tarlib.Entries.Default_Owner, "global gid deleted");
   end Test_Global_PAX_Metadata_Delete;

   procedure Test_Global_PAX_Entry_Keys_Ignored
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
      Reader    : Tarlib.Readers.Reader;
      Info      : Tarlib.Readers.Entry_Info;
      Result    : Tarlib.Errors.Status;
      Has_Entry : Boolean;
      Header    : Ada.Streams.Stream_Element_Array (1 .. 512);
      Global    : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes
          ("13 mtime=555" & Character'Val (10)
           & "19 path=global.txt" & Character'Val (10)
           & "26 linkpath=global-target" & Character'Val (10)
           & "16 devmajor=bad" & Character'Val (10)
           & "16 devminor=bad" & Character'Val (10));
      Meta      : Tarlib.Entries.Metadata;
   begin
      Write_PAX_Header
        (Sink, Tarlib.Entries.PAX_Global_Header, Global, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "global PAX header");

      Tarlib.Internal.Headers.Build
        ("actual.txt", Tarlib.Entries.Regular_File, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File),
         Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "file header");
      Tarlib.Test_Outputs.Write (Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write file");

      Tarlib.Internal.Headers.Build
        ("link", Tarlib.Entries.Symbolic_Link, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Symbolic_Link),
         "real-target", Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "link header");
      Tarlib.Test_Outputs.Write (Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write link");

      Tarlib.Internal.Headers.Build
        ("dev/node", Tarlib.Entries.Character_Device, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Character_Device),
         "", (Major => 1, Minor => 2), Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "device header");
      Tarlib.Test_Outputs.Write (Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write device");

      Tarlib.Test_Outputs.Write
        (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "first terminator");
      Tarlib.Test_Outputs.Write
        (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "second terminator");

      Tarlib.Test_Outputs.Rewind (Sink);
      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");
      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert (Result.Code = Tarlib.Errors.Success and then Has_Entry, "file");
      Assert (Tarlib.Readers.Path (Info) = "actual.txt", "path not global");
      Meta := Tarlib.Readers.Metadata (Info);
      Assert (Meta.MTime = 555, "global mtime still applies");

      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert (Result.Code = Tarlib.Errors.Success and then Has_Entry, "link");
      Assert (Tarlib.Readers.Path (Info) = "link", "link path not global");
      Assert
        (Tarlib.Readers.Link_Path (Info) = "real-target",
         "linkpath not global");
      Meta := Tarlib.Readers.Metadata (Info);
      Assert (Meta.MTime = 555, "global mtime applies to link");

      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert (Result.Code = Tarlib.Errors.Success and then Has_Entry, "device");
      Assert
        (Tarlib.Readers.Kind (Info) = Tarlib.Entries.Character_Device,
         "device kind");
      Assert (Tarlib.Readers.Device (Info).Major = 1, "devmajor not global");
      Assert (Tarlib.Readers.Device (Info).Minor = 2, "devminor not global");
      Meta := Tarlib.Readers.Metadata (Info);
      Assert (Meta.MTime = 555, "global mtime applies to device");
   end Test_Global_PAX_Entry_Keys_Ignored;

   procedure Test_Dangling_Local_Extension_Rejected
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      procedure Write_Terminator
        (Sink   : in out Tarlib.Test_Outputs.Memory_Sink;
         Result : out Tarlib.Errors.Status)
      is
      begin
         Tarlib.Test_Outputs.Write
           (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
         if Result.Code = Tarlib.Errors.Success then
            Tarlib.Test_Outputs.Write
              (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
         end if;
      end Write_Terminator;

      procedure Check_Rejected
        (Sink    : in out Tarlib.Test_Outputs.Memory_Sink;
         Message : String)
      is
         Reader    : Tarlib.Readers.Reader;
         Info      : Tarlib.Readers.Entry_Info;
         Result    : Tarlib.Errors.Status;
         Has_Entry : Boolean;
      begin
         Tarlib.Test_Outputs.Rewind (Sink);
         Tarlib.Readers.Initialize (Reader, Sink, Result);
         Assert (Result.Code = Tarlib.Errors.Success, Message & " initialize");
         Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
         Assert
           (Result.Code = Tarlib.Errors.Invalid_Archive,
            Message & " rejected");
         Assert
           (Tarlib.Readers.State (Reader) = Tarlib.Readers.Failed,
            Message & " failed state");
      end Check_Rejected;

      PAX_Sink    : aliased Tarlib.Test_Outputs.Memory_Sink;
      GNU_Sink    : aliased Tarlib.Test_Outputs.Memory_Sink;
      Global_Sink : aliased Tarlib.Test_Outputs.Memory_Sink;
      Reader      : Tarlib.Readers.Reader;
      Info        : Tarlib.Readers.Entry_Info;
      Result      : Tarlib.Errors.Status;
      Has_Entry   : Boolean;
      PAX_Data    : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes
          ("16 path=missing" & Character'Val (10));
      GNU_Data    : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes ("missing" & Character'Val (0));
      Global_Data : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes ("13 mtime=555" & Character'Val (10));
   begin
      Write_PAX_Header
        (PAX_Sink, Tarlib.Entries.PAX_Extended_Header, PAX_Data, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "local PAX header");
      Write_Terminator (PAX_Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "local PAX terminator");
      Check_Rejected (PAX_Sink, "dangling local PAX");

      Write_Header_Entry
        (GNU_Sink, Tarlib.Entries.GNU_Long_Name,
         Tarlib.Byte_Count (GNU_Data'Length), Result);
      Assert (Result.Code = Tarlib.Errors.Success, "GNU long name header");
      Write_Padded_Data (GNU_Sink, GNU_Data, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "GNU long name data");
      Write_Terminator (GNU_Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "GNU long name terminator");
      Check_Rejected (GNU_Sink, "dangling GNU long name");

      Write_PAX_Header
        (Global_Sink, Tarlib.Entries.PAX_Global_Header, Global_Data, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "global PAX header");
      Write_Terminator (Global_Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "global PAX terminator");

      Tarlib.Test_Outputs.Rewind (Global_Sink);
      Tarlib.Readers.Initialize (Reader, Global_Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "global initialize");
      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert
        (Result.Code = Tarlib.Errors.Success and then not Has_Entry,
         "global PAX may precede archive end");
      Assert (Tarlib.Readers.At_End (Reader), "global PAX finished");
   end Test_Dangling_Local_Extension_Rejected;

   procedure Test_Legacy_V7_Header
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
      Reader    : Tarlib.Readers.Reader;
      Info      : Tarlib.Readers.Entry_Info;
      Result    : Tarlib.Errors.Status;
      Has_Entry : Boolean;
      Header    : Ada.Streams.Stream_Element_Array (1 .. 512);
      Payload   : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes ("old");
      Buffer    : Ada.Streams.Stream_Element_Array (1 .. 3);
      Last      : Ada.Streams.Stream_Element_Offset;
   begin
      Tarlib.Internal.Headers.Build
        ("legacy.txt", Tarlib.Entries.Regular_File, 3,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File),
         Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "USTAR header builds");

      Header (149 .. 156) := [others => 32];
      Header (258 .. 345) := [others => 0];
      Tarlib.Internal.Fields.Put_Octal
        (Header (149 .. 156),
         Tarlib.Internal.Checksums.Compute (Header),
         Tarlib.Internal.Fields.Checksum_Terminated, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "legacy checksum");

      Tarlib.Test_Outputs.Write (Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write legacy header");
      Write_Padded_Data (Sink, Payload, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write legacy payload");
      Tarlib.Test_Outputs.Write
        (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "first terminator");
      Tarlib.Test_Outputs.Write
        (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "second terminator");

      Tarlib.Test_Outputs.Rewind (Sink);
      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");
      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert (Result.Code = Tarlib.Errors.Success and then Has_Entry, "entry");
      Assert (Tarlib.Readers.Path (Info) = "legacy.txt", "legacy path");
      Assert (Tarlib.Readers.Size (Info) = 3, "legacy size");
      Tarlib.Readers.Read (Reader, Buffer, Last, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "read legacy content");
      Assert (Last = 3 and then Buffer = Payload, "legacy payload");
   end Test_Legacy_V7_Header;

   procedure Test_Old_GNU_Magic_Header
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
      Reader    : Tarlib.Readers.Reader;
      Info      : Tarlib.Readers.Entry_Info;
      Result    : Tarlib.Errors.Status;
      Has_Entry : Boolean;
      Header    : Ada.Streams.Stream_Element_Array (1 .. 512);
      Payload   : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes ("gnu");
      Buffer    : Ada.Streams.Stream_Element_Array (1 .. 3);
      Last      : Ada.Streams.Stream_Element_Offset;
   begin
      Tarlib.Internal.Headers.Build
        ("oldgnu.txt", Tarlib.Entries.Regular_File, 3,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File),
         Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "USTAR header builds");

      Header (149 .. 156) := [others => 32];
      Header (263) := Character'Pos (' ');
      Header (264) := Character'Pos (' ');
      Header (265) := 0;
      Tarlib.Internal.Fields.Put_Octal
        (Header (149 .. 156),
         Tarlib.Internal.Checksums.Compute (Header),
         Tarlib.Internal.Fields.Checksum_Terminated, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "old GNU checksum");

      Tarlib.Test_Outputs.Write (Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write old GNU header");
      Write_Padded_Data (Sink, Payload, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write old GNU payload");
      Tarlib.Test_Outputs.Write
        (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "first terminator");
      Tarlib.Test_Outputs.Write
        (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "second terminator");

      Tarlib.Test_Outputs.Rewind (Sink);
      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");
      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert (Result.Code = Tarlib.Errors.Success and then Has_Entry, "entry");
      Assert (Tarlib.Readers.Path (Info) = "oldgnu.txt", "old GNU path");
      Assert (Tarlib.Readers.Size (Info) = 3, "old GNU size");
      Tarlib.Readers.Read (Reader, Buffer, Last, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "read old GNU content");
      Assert (Last = 3 and then Buffer = Payload, "old GNU payload");
   end Test_Old_GNU_Magic_Header;

   procedure Test_Contiguous_File_Typeflag
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
      Reader    : Tarlib.Readers.Reader;
      Info      : Tarlib.Readers.Entry_Info;
      Result    : Tarlib.Errors.Status;
      Has_Entry : Boolean;
      Header    : Ada.Streams.Stream_Element_Array (1 .. 512);
      Payload   : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes ("cntg");
      Buffer    : Ada.Streams.Stream_Element_Array (1 .. 4);
      Last      : Ada.Streams.Stream_Element_Offset;
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
      Assert (Result.Code = Tarlib.Errors.Success, "contiguous checksum");

      Tarlib.Test_Outputs.Write (Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write header");
      Write_Padded_Data (Sink, Payload, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write payload");
      Tarlib.Test_Outputs.Write
        (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "first terminator");
      Tarlib.Test_Outputs.Write
        (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "second terminator");

      Tarlib.Test_Outputs.Rewind (Sink);
      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");
      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert (Result.Code = Tarlib.Errors.Success and then Has_Entry, "entry");
      Assert
        (Tarlib.Readers.Kind (Info) = Tarlib.Entries.Regular_File,
         "contiguous file read as regular");
      Assert (Tarlib.Readers.Path (Info) = "contiguous.bin", "path");
      Assert (Tarlib.Readers.Size (Info) = 4, "size");
      Tarlib.Readers.Read (Reader, Buffer, Last, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "read content");
      Assert (Last = 4 and then Buffer = Payload, "payload");
   end Test_Contiguous_File_Typeflag;

   procedure Test_Legacy_V7_Hard_Link
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
      Reader    : Tarlib.Readers.Reader;
      Info      : Tarlib.Readers.Entry_Info;
      Result    : Tarlib.Errors.Status;
      Has_Entry : Boolean;
      Header    : Ada.Streams.Stream_Element_Array (1 .. 512);
   begin
      Tarlib.Internal.Headers.Build
        ("alias.txt", Tarlib.Entries.Hard_Link, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Hard_Link),
         "target.txt", Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "hard link header builds");

      Header (149 .. 156) := [others => 32];
      Header (258 .. 345) := [others => 0];
      Tarlib.Internal.Fields.Put_Octal
        (Header (149 .. 156),
         Tarlib.Internal.Checksums.Compute (Header),
         Tarlib.Internal.Fields.Checksum_Terminated, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "legacy checksum");

      Tarlib.Test_Outputs.Write (Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write legacy hard link");
      Tarlib.Test_Outputs.Write
        (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "first terminator");
      Tarlib.Test_Outputs.Write
        (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "second terminator");

      Tarlib.Test_Outputs.Rewind (Sink);
      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");
      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert (Result.Code = Tarlib.Errors.Success and then Has_Entry, "entry");
      Assert
        (Tarlib.Readers.Kind (Info) = Tarlib.Entries.Hard_Link,
         "hard link kind");
      Assert (Tarlib.Readers.Path (Info) = "alias.txt", "link path");
      Assert (Tarlib.Readers.Link_Path (Info) = "target.txt", "link target");
   end Test_Legacy_V7_Hard_Link;

   procedure Test_Hard_Link_With_Data_Blocks
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
      Reader    : Tarlib.Readers.Reader;
      Info      : Tarlib.Readers.Entry_Info;
      Result    : Tarlib.Errors.Status;
      Has_Entry : Boolean;
      Header    : Ada.Streams.Stream_Element_Array (1 .. 512);
      Link_Data : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes ("link");
      File_Data : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes ("next");
      Buffer    : Ada.Streams.Stream_Element_Array (1 .. 4);
      Last      : Ada.Streams.Stream_Element_Offset;
   begin
      Tarlib.Internal.Headers.Build
        ("alias.txt", Tarlib.Entries.Hard_Link, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Hard_Link),
         "target.txt", Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "hard link header builds");

      Header (149 .. 156) := [others => 32];
      Tarlib.Internal.Fields.Put_Octal
        (Header (125 .. 136), 4, Tarlib.Internal.Fields.NUL_Terminated,
         Result);
      Assert (Result.Code = Tarlib.Errors.Success, "hard link size");
      Tarlib.Internal.Fields.Put_Octal
        (Header (149 .. 156),
         Tarlib.Internal.Checksums.Compute (Header),
         Tarlib.Internal.Fields.Checksum_Terminated, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "hard link checksum");

      Tarlib.Test_Outputs.Write (Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write hard link header");
      Write_Padded_Data (Sink, Link_Data, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write hard link data");

      Tarlib.Internal.Headers.Build
        ("next.txt", Tarlib.Entries.Regular_File, 4,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File),
         Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "file header builds");
      Tarlib.Test_Outputs.Write (Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write file header");
      Write_Padded_Data (Sink, File_Data, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write file data");
      Tarlib.Test_Outputs.Write
        (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "first terminator");
      Tarlib.Test_Outputs.Write
        (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "second terminator");

      Tarlib.Test_Outputs.Rewind (Sink);
      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");
      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert
        (Result.Code = Tarlib.Errors.Success and then Has_Entry,
         "hard link entry");
      Assert
        (Tarlib.Readers.Kind (Info) = Tarlib.Entries.Hard_Link,
         "hard link kind");
      Assert (Tarlib.Readers.Size (Info) = 4, "hard link data size");
      Assert (Tarlib.Readers.Link_Path (Info) = "target.txt", "link target");

      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert
        (Result.Code = Tarlib.Errors.Success and then Has_Entry,
         "next entry after hard link data");
      Assert (Tarlib.Readers.Path (Info) = "next.txt", "next path");
      Tarlib.Readers.Read (Reader, Buffer, Last, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "read next content");
      Assert (Last = 4 and then Buffer = File_Data, "next payload");
   end Test_Hard_Link_With_Data_Blocks;

   procedure Test_PAX_Hard_Link_Size_Data_Blocks
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
      Reader    : Tarlib.Readers.Reader;
      Info      : Tarlib.Readers.Entry_Info;
      Result    : Tarlib.Errors.Status;
      Has_Entry : Boolean;
      Header    : Ada.Streams.Stream_Element_Array (1 .. 512);
      PAX_Data  : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes
          ("9 size=4" & Character'Val (10));
      Link_Data : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes ("link");
      File_Data : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes ("next");
      Buffer    : Ada.Streams.Stream_Element_Array (1 .. 4);
      Last      : Ada.Streams.Stream_Element_Offset;
   begin
      Write_PAX_Header
        (Sink, Tarlib.Entries.PAX_Extended_Header, PAX_Data, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "PAX size header");
      Tarlib.Internal.Headers.Build
        ("alias.txt", Tarlib.Entries.Hard_Link, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Hard_Link),
         "target.txt", Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "hard link header builds");
      Tarlib.Test_Outputs.Write (Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write hard link header");
      Write_Padded_Data (Sink, Link_Data, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write hard link data");

      Tarlib.Internal.Headers.Build
        ("next.txt", Tarlib.Entries.Regular_File, 4,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File),
         Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "file header builds");
      Tarlib.Test_Outputs.Write (Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write file header");
      Write_Padded_Data (Sink, File_Data, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write file data");
      Tarlib.Test_Outputs.Write
        (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "first terminator");
      Tarlib.Test_Outputs.Write
        (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "second terminator");

      Tarlib.Test_Outputs.Rewind (Sink);
      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");
      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert
        (Result.Code = Tarlib.Errors.Success and then Has_Entry,
         "hard link entry");
      Assert
        (Tarlib.Readers.Kind (Info) = Tarlib.Entries.Hard_Link,
         "hard link kind");
      Assert (Tarlib.Readers.Size (Info) = 4, "PAX hard link data size");

      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert
        (Result.Code = Tarlib.Errors.Success and then Has_Entry,
         "next entry after PAX hard link data");
      Assert (Tarlib.Readers.Path (Info) = "next.txt", "next path");
      Tarlib.Readers.Read (Reader, Buffer, Last, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "read next content");
      Assert (Last = 4 and then Buffer = File_Data, "next payload");
   end Test_PAX_Hard_Link_Size_Data_Blocks;

   procedure Test_Legacy_V7_Directory
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
      Reader    : Tarlib.Readers.Reader;
      Info      : Tarlib.Readers.Entry_Info;
      Result    : Tarlib.Errors.Status;
      Has_Entry : Boolean;
      Header    : Ada.Streams.Stream_Element_Array (1 .. 512);
      Buffer    : Ada.Streams.Stream_Element_Array (1 .. 1);
      Last      : Ada.Streams.Stream_Element_Offset;
   begin
      Tarlib.Internal.Headers.Build
        ("legacy-dir/", Tarlib.Entries.Regular_File, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Directory),
         Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "directory header builds");

      Header (149 .. 156) := [others => 32];
      Header (157) := 0;
      Header (258 .. 345) := [others => 0];
      Tarlib.Internal.Fields.Put_Octal
        (Header (149 .. 156),
         Tarlib.Internal.Checksums.Compute (Header),
         Tarlib.Internal.Fields.Checksum_Terminated, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "legacy checksum");

      Tarlib.Test_Outputs.Write (Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write legacy directory");
      Tarlib.Test_Outputs.Write
        (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "first terminator");
      Tarlib.Test_Outputs.Write
        (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "second terminator");

      Tarlib.Test_Outputs.Rewind (Sink);
      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");
      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert (Result.Code = Tarlib.Errors.Success and then Has_Entry, "entry");
      Assert
        (Tarlib.Readers.Kind (Info) = Tarlib.Entries.Directory,
         "legacy directory kind");
      Assert (Tarlib.Readers.Path (Info) = "legacy-dir/", "directory path");
      Tarlib.Readers.Read (Reader, Buffer, Last, Result);
      Assert
        (Result.Code = Tarlib.Errors.Invalid_Entry_Kind,
         "legacy directory read rejected");
   end Test_Legacy_V7_Directory;

   procedure Test_Base_256_Size_Header
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
      Reader    : Tarlib.Readers.Reader;
      Info      : Tarlib.Readers.Entry_Info;
      Result    : Tarlib.Errors.Status;
      Has_Entry : Boolean;
      Header    : Ada.Streams.Stream_Element_Array (1 .. 512);
      Payload   : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes ("abcd");
      Buffer    : Ada.Streams.Stream_Element_Array (1 .. 4);
      Last      : Ada.Streams.Stream_Element_Offset;
   begin
      Tarlib.Internal.Headers.Build
        ("base256.bin", Tarlib.Entries.Regular_File, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File),
         Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "header builds");

      Header (125 .. 136) := [16#80#, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4];
      Header (149 .. 156) := [others => 32];
      Tarlib.Internal.Fields.Put_Octal
        (Header (149 .. 156),
         Tarlib.Internal.Checksums.Compute (Header),
         Tarlib.Internal.Fields.Checksum_Terminated, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "checksum");

      Tarlib.Test_Outputs.Write (Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write header");
      Write_Padded_Data (Sink, Payload, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write payload");
      Tarlib.Test_Outputs.Write
        (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "first terminator");
      Tarlib.Test_Outputs.Write
        (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "second terminator");

      Tarlib.Test_Outputs.Rewind (Sink);
      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");
      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert (Result.Code = Tarlib.Errors.Success and then Has_Entry, "entry");
      Assert (Tarlib.Readers.Size (Info) = 4, "base-256 size");
      Tarlib.Readers.Read (Reader, Buffer, Last, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "read payload");
      Assert (Last = 4 and then Buffer = Payload, "payload");
   end Test_Base_256_Size_Header;

   procedure Test_Base_256_Metadata_Header
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
      Reader    : Tarlib.Readers.Reader;
      Info      : Tarlib.Readers.Entry_Info;
      Result    : Tarlib.Errors.Status;
      Has_Entry : Boolean;
      Header    : Ada.Streams.Stream_Element_Array (1 .. 512);
      Meta      : Tarlib.Entries.Metadata;
   begin
      Tarlib.Internal.Headers.Build
        ("base256-meta.bin", Tarlib.Entries.Regular_File, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File),
         Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "header builds");

      Header (109 .. 116) := [16#80#, 0, 0, 0, 0, 16#2D#, 16#C6#, 16#C0#];
      Header (117 .. 124) := [16#80#, 0, 0, 0, 0, 16#3D#, 16#09#, 0];
      Header (137 .. 148) :=
        [16#80#, 0, 0, 0, 0, 0, 0, 1, 16#2A#, 5, 16#F2#, 0];
      Header (149 .. 156) := [others => 32];
      Tarlib.Internal.Fields.Put_Octal
        (Header (149 .. 156),
         Tarlib.Internal.Checksums.Compute (Header),
         Tarlib.Internal.Fields.Checksum_Terminated, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "checksum");

      Tarlib.Test_Outputs.Write (Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write header");
      Tarlib.Test_Outputs.Write
        (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "first terminator");
      Tarlib.Test_Outputs.Write
        (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "second terminator");

      Tarlib.Test_Outputs.Rewind (Sink);
      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");
      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert (Result.Code = Tarlib.Errors.Success and then Has_Entry, "entry");
      Meta := Tarlib.Readers.Metadata (Info);
      Assert (Meta.UID = 3_000_000, "base-256 uid");
      Assert (Meta.GID = 4_000_000, "base-256 gid");
      Assert (Meta.MTime = 5_000_000_000, "base-256 mtime");
   end Test_Base_256_Metadata_Header;

   procedure Test_Signed_Checksum_Header
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
      Reader    : Tarlib.Readers.Reader;
      Info      : Tarlib.Readers.Entry_Info;
      Result    : Tarlib.Errors.Status;
      Has_Entry : Boolean;
      Header    : Ada.Streams.Stream_Element_Array (1 .. 512);
      Payload   : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes ("abcd");
      Signed_Checksum : Interfaces.Integer_64;
   begin
      Tarlib.Internal.Headers.Build
        ("signed-sum.bin", Tarlib.Entries.Regular_File, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File),
         Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "header builds");

      Header (125 .. 136) := [16#80#, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4];
      Header (149 .. 156) := [others => 32];
      Signed_Checksum := Tarlib.Internal.Checksums.Compute_Signed (Header);
      Assert (Signed_Checksum > 0, "signed checksum is positive");
      Tarlib.Internal.Fields.Put_Octal
        (Header (149 .. 156), Interfaces.Unsigned_64 (Signed_Checksum),
         Tarlib.Internal.Fields.Checksum_Terminated, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "signed checksum stored");

      Tarlib.Test_Outputs.Write (Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write header");
      Write_Padded_Data (Sink, Payload, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write payload");
      Tarlib.Test_Outputs.Write
        (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "first terminator");
      Tarlib.Test_Outputs.Write
        (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "second terminator");

      Tarlib.Test_Outputs.Rewind (Sink);
      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");
      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert (Result.Code = Tarlib.Errors.Success and then Has_Entry, "entry");
      Assert (Tarlib.Readers.Size (Info) = 4, "base-256 size");
   end Test_Signed_Checksum_Header;

   procedure Test_GNU_Sparse_Header_Rejected_Without_Map
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
      Reader    : Tarlib.Readers.Reader;
      Info      : Tarlib.Readers.Entry_Info;
      Result    : Tarlib.Errors.Status;
      Has_Entry : Boolean;
      Header    : Ada.Streams.Stream_Element_Array (1 .. 512);
   begin
      Tarlib.Internal.Headers.Build
        ("sparse.bin", Tarlib.Entries.GNU_Sparse, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.GNU_Sparse),
         Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "sparse header builds");
      Tarlib.Test_Outputs.Write (Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write sparse header");

      Tarlib.Test_Outputs.Rewind (Sink);
      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");
      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert
        (Result.Code = Tarlib.Errors.Invalid_Entry_Kind,
         "GNU sparse is explicitly unsupported");
   end Test_GNU_Sparse_Header_Rejected_Without_Map;

   procedure Test_GNU_Sparse_PAX_Reconstructed
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
      Reader    : Tarlib.Readers.Reader;
      Info      : Tarlib.Readers.Entry_Info;
      Result    : Tarlib.Errors.Status;
      Has_Entry : Boolean;
      Header    : Ada.Streams.Stream_Element_Array (1 .. 512);
      Payload   : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes ("abcde");
      Buffer    : Ada.Streams.Stream_Element_Array (1 .. 10);
      Last      : Ada.Streams.Stream_Element_Offset;
      PAX_Data  : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes
          ("22 GNU.sparse.size=10" & Character'Val (10)
           & "26 GNU.sparse.map=2,3,8,2" & Character'Val (10));
   begin
      Write_PAX_Header
        (Sink, Tarlib.Entries.PAX_Extended_Header, PAX_Data, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "sparse PAX header");
      Tarlib.Internal.Headers.Build
        ("sparse.bin", Tarlib.Entries.Regular_File, 5,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File),
         Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "file header builds");
      Tarlib.Test_Outputs.Write (Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write file header");
      Write_Padded_Data (Sink, Payload, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write sparse payload");
      Tarlib.Internal.Headers.Build
        ("next.txt", Tarlib.Entries.Regular_File, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File),
         Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "next header builds");
      Tarlib.Test_Outputs.Write (Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write next header");
      Tarlib.Test_Outputs.Write
        (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "first terminator");
      Tarlib.Test_Outputs.Write
        (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "second terminator");

      Tarlib.Test_Outputs.Rewind (Sink);
      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");
      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert (Result.Code = Tarlib.Errors.Success and then Has_Entry, "entry");
      Assert (Tarlib.Readers.Path (Info) = "sparse.bin", "sparse path");
      Assert (Tarlib.Readers.Kind (Info) = Tarlib.Entries.Regular_File,
              "sparse exposed as regular file");
      Assert (Tarlib.Readers.Size (Info) = 10, "logical sparse size");
      Tarlib.Readers.Read (Reader, Buffer, Last, Result);
      Assert
        (Result.Code = Tarlib.Errors.Success and then Last = 10,
         "read sparse data");
      Assert
        (Buffer =
           [0, 0, Character'Pos ('a'), Character'Pos ('b'),
            Character'Pos ('c'), 0, 0, 0, Character'Pos ('d'),
            Character'Pos ('e')],
         "sparse holes reconstructed");
      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert
        (Result.Code = Tarlib.Errors.Success and then Has_Entry,
         "next entry after sparse");
      Assert (Tarlib.Readers.Path (Info) = "next.txt", "next path");
   end Test_GNU_Sparse_PAX_Reconstructed;

   procedure Test_Star_Sparse_PAX_Reconstructed
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
      Reader    : Tarlib.Readers.Reader;
      Info      : Tarlib.Readers.Entry_Info;
      Result    : Tarlib.Errors.Status;
      Has_Entry : Boolean;
      Header    : Ada.Streams.Stream_Element_Array (1 .. 512);
      Payload   : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes ("abcde");
      Buffer    : Ada.Streams.Stream_Element_Array (1 .. 10);
      Last      : Ada.Streams.Stream_Element_Offset;
      PAX_Data  : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes
          ("26 SCHILY.filetype=sparse" & Character'Val (10)
           & "22 SCHILY.realsize=10" & Character'Val (10)
           & "19 SCHILY.offset=2" & Character'Val (10)
           & "21 SCHILY.numbytes=3" & Character'Val (10)
           & "19 SCHILY.offset=8" & Character'Val (10)
           & "21 SCHILY.numbytes=2" & Character'Val (10));
   begin
      Write_PAX_Header
        (Sink, Tarlib.Entries.PAX_Extended_Header, PAX_Data, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "star sparse PAX");
      Tarlib.Internal.Headers.Build
        ("star-sparse.bin", Tarlib.Entries.Regular_File, 5,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File),
         Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "file header builds");
      Tarlib.Test_Outputs.Write (Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write file header");
      Write_Padded_Data (Sink, Payload, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write sparse payload");
      Write_Terminator (Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "terminator");

      Tarlib.Test_Outputs.Rewind (Sink);
      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");
      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert (Result.Code = Tarlib.Errors.Success and then Has_Entry, "entry");
      Assert (Tarlib.Readers.Size (Info) = 10, "logical sparse size");
      Tarlib.Readers.Read (Reader, Buffer, Last, Result);
      Assert
        (Result.Code = Tarlib.Errors.Success and then Last = 10,
         "read sparse data");
      Assert
        (Buffer =
           [0, 0, Character'Pos ('a'), Character'Pos ('b'),
            Character'Pos ('c'), 0, 0, 0, Character'Pos ('d'),
            Character'Pos ('e')],
         "star sparse holes reconstructed");
   end Test_Star_Sparse_PAX_Reconstructed;

   procedure Test_Old_GNU_Sparse_Header_Reconstructed
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
      Reader    : Tarlib.Readers.Reader;
      Info      : Tarlib.Readers.Entry_Info;
      Result    : Tarlib.Errors.Status;
      Has_Entry : Boolean;
      Header    : Ada.Streams.Stream_Element_Array (1 .. 512);
      Payload   : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes ("abcde");
      Buffer    : Ada.Streams.Stream_Element_Array (1 .. 10);
      Last      : Ada.Streams.Stream_Element_Offset;
   begin
      Tarlib.Internal.Headers.Build
        ("oldsparse.bin", Tarlib.Entries.GNU_Sparse, 5,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.GNU_Sparse),
         Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "sparse header builds");
      Header (263) := Character'Pos (' ');
      Header (264) := Character'Pos (' ');
      Header (265) := 0;
      Tarlib.Internal.Fields.Put_Octal
        (Header (387 .. 398), 2, Tarlib.Internal.Fields.NUL_Terminated,
         Result);
      Assert (Result.Code = Tarlib.Errors.Success, "first offset");
      Tarlib.Internal.Fields.Put_Octal
        (Header (399 .. 410), 3, Tarlib.Internal.Fields.NUL_Terminated,
         Result);
      Assert (Result.Code = Tarlib.Errors.Success, "first length");
      Tarlib.Internal.Fields.Put_Octal
        (Header (411 .. 422), 8, Tarlib.Internal.Fields.NUL_Terminated,
         Result);
      Assert (Result.Code = Tarlib.Errors.Success, "second offset");
      Tarlib.Internal.Fields.Put_Octal
        (Header (423 .. 434), 2, Tarlib.Internal.Fields.NUL_Terminated,
         Result);
      Assert (Result.Code = Tarlib.Errors.Success, "second length");
      Tarlib.Internal.Fields.Put_Octal
        (Header (484 .. 495), 10, Tarlib.Internal.Fields.NUL_Terminated,
         Result);
      Assert (Result.Code = Tarlib.Errors.Success, "real size");
      Header (149 .. 156) := [others => 32];
      Tarlib.Internal.Fields.Put_Octal
        (Header (149 .. 156), Tarlib.Internal.Checksums.Compute (Header),
         Tarlib.Internal.Fields.Checksum_Terminated, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "checksum");
      Tarlib.Test_Outputs.Write (Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write sparse header");
      Write_Padded_Data (Sink, Payload, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write sparse payload");
      Write_Terminator (Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "terminator");

      Tarlib.Test_Outputs.Rewind (Sink);
      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");
      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert (Result.Code = Tarlib.Errors.Success and then Has_Entry, "entry");
      Assert (Tarlib.Readers.Kind (Info) = Tarlib.Entries.Regular_File,
              "old sparse exposed as regular file");
      Assert (Tarlib.Readers.Size (Info) = 10, "logical sparse size");
      Tarlib.Readers.Read (Reader, Buffer, Last, Result);
      Assert
        (Result.Code = Tarlib.Errors.Success and then Last = 10,
         "read sparse data");
      Assert
        (Buffer =
           [0, 0, Character'Pos ('a'), Character'Pos ('b'),
            Character'Pos ('c'), 0, 0, 0, Character'Pos ('d'),
            Character'Pos ('e')],
         "old sparse holes reconstructed");
   end Test_Old_GNU_Sparse_Header_Reconstructed;

   procedure Test_Old_GNU_Sparse_Extension_Reconstructed
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
      Reader    : Tarlib.Readers.Reader;
      Info      : Tarlib.Readers.Entry_Info;
      Result    : Tarlib.Errors.Status;
      Has_Entry : Boolean;
      Header    : Ada.Streams.Stream_Element_Array (1 .. 512);
      Extension : Ada.Streams.Stream_Element_Array (1 .. 512) := [others => 0];
      Payload   : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes ("abcdef");
      Buffer    : Ada.Streams.Stream_Element_Array (1 .. 12);
      Last      : Ada.Streams.Stream_Element_Offset;
   begin
      Tarlib.Internal.Headers.Build
        ("oldsparse-ext.bin", Tarlib.Entries.GNU_Sparse, 6,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.GNU_Sparse),
         Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "sparse header builds");
      Header (263) := Character'Pos (' ');
      Header (264) := Character'Pos (' ');
      Header (265) := 0;
      Tarlib.Internal.Fields.Put_Octal
        (Header (387 .. 398), 1, Tarlib.Internal.Fields.NUL_Terminated,
         Result);
      Assert (Result.Code = Tarlib.Errors.Success, "header offset");
      Tarlib.Internal.Fields.Put_Octal
        (Header (399 .. 410), 3, Tarlib.Internal.Fields.NUL_Terminated,
         Result);
      Assert (Result.Code = Tarlib.Errors.Success, "header length");
      Header (483) := 1;
      Tarlib.Internal.Fields.Put_Octal
        (Header (484 .. 495), 12, Tarlib.Internal.Fields.NUL_Terminated,
         Result);
      Assert (Result.Code = Tarlib.Errors.Success, "real size");
      Header (149 .. 156) := [others => 32];
      Tarlib.Internal.Fields.Put_Octal
        (Header (149 .. 156), Tarlib.Internal.Checksums.Compute (Header),
         Tarlib.Internal.Fields.Checksum_Terminated, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "checksum");
      Tarlib.Internal.Fields.Put_Octal
        (Extension (1 .. 12), 9, Tarlib.Internal.Fields.NUL_Terminated,
         Result);
      Assert (Result.Code = Tarlib.Errors.Success, "extension offset");
      Tarlib.Internal.Fields.Put_Octal
        (Extension (13 .. 24), 3, Tarlib.Internal.Fields.NUL_Terminated,
         Result);
      Assert (Result.Code = Tarlib.Errors.Success, "extension length");

      Tarlib.Test_Outputs.Write (Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write sparse header");
      Tarlib.Test_Outputs.Write (Sink, Extension, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write sparse extension");
      Write_Padded_Data (Sink, Payload, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write sparse payload");
      Write_Terminator (Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "terminator");

      Tarlib.Test_Outputs.Rewind (Sink);
      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");
      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert (Result.Code = Tarlib.Errors.Success and then Has_Entry, "entry");
      Assert (Tarlib.Readers.Size (Info) = 12, "logical sparse size");
      Tarlib.Readers.Read (Reader, Buffer, Last, Result);
      Assert
        (Result.Code = Tarlib.Errors.Success and then Last = 12,
         "read sparse data");
      Assert
        (Buffer =
           [0, Character'Pos ('a'), Character'Pos ('b'),
            Character'Pos ('c'), 0, 0, 0, 0, 0,
            Character'Pos ('d'), Character'Pos ('e'), Character'Pos ('f')],
         "extended sparse holes reconstructed");
   end Test_Old_GNU_Sparse_Extension_Reconstructed;

   procedure Test_Multi_Volume_Offsets
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      PAX_Sink  : aliased Tarlib.Test_Outputs.Memory_Sink;
      GNU_Sink  : aliased Tarlib.Test_Outputs.Memory_Sink;
      PAX_Reader : Tarlib.Readers.Reader;
      GNU_Reader : Tarlib.Readers.Reader;
      Info      : Tarlib.Readers.Entry_Info;
      Result    : Tarlib.Errors.Status;
      Has_Entry : Boolean;
      Header    : Ada.Streams.Stream_Element_Array (1 .. 512);
      Payload   : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes ("part");
      PAX_Data  : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes
          ("25 GNU.volume.offset=123" & Character'Val (10));
   begin
      Write_PAX_Header
        (PAX_Sink, Tarlib.Entries.PAX_Extended_Header, PAX_Data, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "volume offset PAX");
      Tarlib.Internal.Headers.Build
        ("part.bin", Tarlib.Entries.Multi_Volume, 4,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Multi_Volume),
         Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "multi header");
      Tarlib.Test_Outputs.Write (PAX_Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write multi header");
      Write_Padded_Data (PAX_Sink, Payload, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write multi data");
      Write_Terminator (PAX_Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "PAX terminator");

      Tarlib.Test_Outputs.Rewind (PAX_Sink);
      Tarlib.Readers.Initialize (PAX_Reader, PAX_Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "PAX reader initialize");
      Tarlib.Readers.Next_Entry (PAX_Reader, Info, Has_Entry, Result);
      Assert (Result.Code = Tarlib.Errors.Success and then Has_Entry,
              "PAX multi entry");
      Assert
        (Tarlib.Readers.Multi_Volume_Offset (Info) = 123,
         "PAX volume offset");

      Tarlib.Internal.Headers.Build
        ("oldpart.bin", Tarlib.Entries.Multi_Volume, 4,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Multi_Volume),
         Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "old multi header");
      Header (263) := Character'Pos (' ');
      Header (264) := Character'Pos (' ');
      Header (265) := 0;
      Tarlib.Internal.Fields.Put_Octal
        (Header (370 .. 381), 456, Tarlib.Internal.Fields.NUL_Terminated,
         Result);
      Assert (Result.Code = Tarlib.Errors.Success, "old offset");
      Header (149 .. 156) := [others => 32];
      Tarlib.Internal.Fields.Put_Octal
        (Header (149 .. 156), Tarlib.Internal.Checksums.Compute (Header),
         Tarlib.Internal.Fields.Checksum_Terminated, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "old checksum");
      Tarlib.Test_Outputs.Write (GNU_Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write old multi header");
      Write_Padded_Data (GNU_Sink, Payload, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write old multi data");
      Write_Terminator (GNU_Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "old terminator");

      Tarlib.Test_Outputs.Rewind (GNU_Sink);
      Tarlib.Readers.Initialize (GNU_Reader, GNU_Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "old reader initialize");
      Tarlib.Readers.Next_Entry (GNU_Reader, Info, Has_Entry, Result);
      Assert (Result.Code = Tarlib.Errors.Success and then Has_Entry,
              "old multi entry");
      Assert
        (Tarlib.Readers.Multi_Volume_Offset (Info) = 456,
         "old GNU volume offset");
   end Test_Multi_Volume_Offsets;

   procedure Test_Incremental_Dump_Listing
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
      Writer    : Tarlib.Writers.Writer;
      Reader    : Tarlib.Readers.Reader;
      Info      : Tarlib.Readers.Entry_Info;
      Listing   : Tarlib.Readers.Incremental_Listing;
      Result    : Tarlib.Errors.Status;
      Has_Entry : Boolean;
      Data      : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes
          ("Ydir" & Character'Val (0)
           & "Nold" & Character'Val (0)
           & Character'Val (0));
   begin
      Tarlib.Writers.Initialize (Writer, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "writer initialize");
      Tarlib.Writers.Begin_Entry
        (Writer, "dumpdir", Tarlib.Entries.Incremental_Dump,
         Tarlib.Byte_Count (Data'Length),
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Incremental_Dump),
         Result);
      Assert (Result.Code = Tarlib.Errors.Success, "dump entry");
      Tarlib.Writers.Write (Writer, Data, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "dump data");
      Tarlib.Writers.End_Entry (Writer, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "dump end");
      Tarlib.Writers.Finish (Writer, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "finish");

      Tarlib.Test_Outputs.Rewind (Sink);
      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");
      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert (Result.Code = Tarlib.Errors.Success and then Has_Entry, "entry");
      Assert (Tarlib.Readers.Kind (Info) = Tarlib.Entries.Incremental_Dump,
              "incremental kind");
      Tarlib.Readers.Read_Incremental_Dump (Reader, Listing, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "parse dump listing");
      Assert
        (Tarlib.Readers.Incremental_Record_Count (Listing) = 2,
         "record count");
      Assert
        (Tarlib.Readers.Incremental_Record_Is_Directory (Listing, 1),
         "directory marker");
      Assert
        (Tarlib.Readers.Incremental_Record_Path (Listing, 1) = "dir",
         "directory path");
      Assert
        (not Tarlib.Readers.Incremental_Record_Is_Directory (Listing, 2),
         "deleted marker");
      Assert
        (Tarlib.Readers.Incremental_Record_Path (Listing, 2) = "old",
         "deleted path");
   end Test_Incremental_Dump_Listing;

   procedure Test_Volume_Label
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
      Reader    : Tarlib.Readers.Reader;
      Info      : Tarlib.Readers.Entry_Info;
      Result    : Tarlib.Errors.Status;
      Has_Entry : Boolean;
      Header    : Ada.Streams.Stream_Element_Array (1 .. 512);
      Buffer    : Ada.Streams.Stream_Element_Array (1 .. 1);
      Last      : Ada.Streams.Stream_Element_Offset;
   begin
      Tarlib.Internal.Headers.Build
        ("TARLIB_VOLUME", Tarlib.Entries.Volume_Label, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Volume_Label),
         Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "volume label header");
      Tarlib.Test_Outputs.Write (Sink, Header, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write label");
      Tarlib.Test_Outputs.Write
        (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "first terminator");
      Tarlib.Test_Outputs.Write
        (Sink, Tarlib.Internal.Constants.Zero_Block, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "second terminator");

      Tarlib.Test_Outputs.Rewind (Sink);
      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");
      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert (Result.Code = Tarlib.Errors.Success and then Has_Entry, "entry");
      Assert
        (Tarlib.Readers.Kind (Info) = Tarlib.Entries.Volume_Label,
         "volume label kind");
      Assert (Tarlib.Readers.Path (Info) = "TARLIB_VOLUME", "label text");
      Tarlib.Readers.Read (Reader, Buffer, Last, Result);
      Assert
        (Result.Code = Tarlib.Errors.Invalid_Entry_Kind,
         "volume label has no regular data reads");
      Tarlib.Readers.Skip_Entry (Reader, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "skip volume label");
   end Test_Volume_Label;

   procedure Test_Deterministic_Fuzz_Corpus
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      procedure Exercise
        (Sink    : in out Tarlib.Test_Outputs.Memory_Sink;
         Message : String)
      is
         Reader    : Tarlib.Readers.Reader;
         Info      : Tarlib.Readers.Entry_Info;
         Result    : Tarlib.Errors.Status;
         Has_Entry : Boolean;
         Steps     : Natural := 0;
      begin
         Tarlib.Test_Outputs.Rewind (Sink);
         Tarlib.Readers.Initialize (Reader, Sink, Result);
         Assert (Result.Code = Tarlib.Errors.Success, Message & " initialize");

         while Steps < 8 loop
            Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
            exit when Result.Code /= Tarlib.Errors.Success or else not Has_Entry;

            Tarlib.Readers.Skip_Entry (Reader, Result);
            exit when Result.Code /= Tarlib.Errors.Success;
            Steps := Steps + 1;
         end loop;

         Assert
           (Tarlib.Readers.State (Reader) in Tarlib.Readers.Ready
            | Tarlib.Readers.Reading_Entry
            | Tarlib.Readers.Finished
            | Tarlib.Readers.Failed,
            Message & " ends in known state");
      end Exercise;

      procedure Check_Truncated_Header is
         Sink   : aliased Tarlib.Test_Outputs.Memory_Sink;
         Result : Tarlib.Errors.Status;
      begin
         Tarlib.Test_Outputs.Write
           (Sink, [1 .. 128 => Ada.Streams.Stream_Element (Character'Pos ('x'))],
            Result);
         Assert (Result.Code = Tarlib.Errors.Success, "write truncated header");
         Exercise (Sink, "truncated header");
      end Check_Truncated_Header;

      procedure Check_Truncated_Payload is
         Sink   : aliased Tarlib.Test_Outputs.Memory_Sink;
         Header : Ada.Streams.Stream_Element_Array (1 .. 512);
         Result : Tarlib.Errors.Status;
      begin
         Tarlib.Internal.Headers.Build
           ("short.bin", Tarlib.Entries.Regular_File, 32,
            Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File),
            Header, Result);
         Assert (Result.Code = Tarlib.Errors.Success, "payload header");
         Tarlib.Test_Outputs.Write (Sink, Header, Result);
         Assert (Result.Code = Tarlib.Errors.Success, "write payload header");
         Tarlib.Test_Outputs.Write
           (Sink, Tarlib.Test_Fixtures.To_Bytes ("short"), Result);
         Assert (Result.Code = Tarlib.Errors.Success, "write short payload");
         Exercise (Sink, "truncated payload");
      end Check_Truncated_Payload;

      procedure Check_Malformed_PAX is
         Sink     : aliased Tarlib.Test_Outputs.Memory_Sink;
         Header   : Ada.Streams.Stream_Element_Array (1 .. 512);
         PAX_Data : constant Ada.Streams.Stream_Element_Array :=
           Tarlib.Test_Fixtures.To_Bytes
             ("12 path=../x" & Character'Val (10)
              & "14 size=notnum" & Character'Val (10)
              & "24 GNU.sparse.map=9,4,1" & Character'Val (10));
         Result   : Tarlib.Errors.Status;
      begin
         Write_PAX_Header
           (Sink, Tarlib.Entries.PAX_Extended_Header, PAX_Data, Result);
         Assert (Result.Code = Tarlib.Errors.Success, "malformed PAX header");
         Tarlib.Internal.Headers.Build
           ("pax.txt", Tarlib.Entries.Regular_File, 0,
            Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File),
            Header, Result);
         Assert (Result.Code = Tarlib.Errors.Success, "malformed PAX file");
         Tarlib.Test_Outputs.Write (Sink, Header, Result);
         Assert (Result.Code = Tarlib.Errors.Success, "write malformed PAX file");
         Exercise (Sink, "malformed PAX corpus");
      end Check_Malformed_PAX;

      Base   : aliased Tarlib.Test_Outputs.Memory_Sink;
      Mutant : aliased Tarlib.Test_Outputs.Memory_Sink;
      Result : Tarlib.Errors.Status;
   begin
      Check_Truncated_Header;
      Check_Truncated_Payload;
      Check_Malformed_PAX;

      Build_Sample (Base, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "fuzz seed builds");
      declare
         Data  : constant Ada.Streams.Stream_Element_Array :=
           Tarlib.Test_Outputs.Bytes (Base);
         Limit : constant Natural := Natural'Min (Data'Length, 1536);
      begin
         for Index in 1 .. Limit loop
            Tarlib.Test_Outputs.Reset (Mutant);
            Tarlib.Test_Outputs.Write (Mutant, Data, Result);
            Assert (Result.Code = Tarlib.Errors.Success, "copy fuzz seed");
            Tarlib.Test_Outputs.Set_Element
              (Mutant, Index,
               Ada.Streams.Stream_Element
                 ((Natural
                     (Data
                        (Data'First
                         + Ada.Streams.Stream_Element_Offset (Index - 1)))
                   + 73 + Index)
                  mod 256));
            Exercise (Mutant, "mutated archive" & Natural'Image (Index));
         end loop;
      end;
   end Test_Deterministic_Fuzz_Corpus;

   overriding procedure Register_Tests (T : in out Test_Case) is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine
        (T, Test_Empty_Archive'Access, "empty archive");
      Registration.Register_Routine
        (T, Test_Single_Zero_Block_Terminates'Access,
         "single zero block terminates");
      Registration.Register_Routine
        (T, Test_Read_File_Content'Access, "read file content");
      Registration.Register_Routine
        (T, Test_Directory_Read_Rejected'Access, "directory read rejection");
      Registration.Register_Routine
        (T, Test_Invalid_Checksum'Access, "invalid archive rejection");
      Registration.Register_Routine
        (T, Test_PAX_Long_Path'Access, "PAX long path");
      Registration.Register_Routine
        (T, Test_PAX_Long_Link_Path'Access, "PAX long linkpath");
      Registration.Register_Routine
        (T, Test_PAX_Long_Non_File_Paths'Access, "PAX non-file paths");
      Registration.Register_Routine
        (T, Test_PAX_Numeric_Overrides'Access, "PAX numeric overrides");
      Registration.Register_Routine
        (T, Test_PAX_Access_And_Change_Times'Access,
         "PAX access and change times");
      Registration.Register_Routine
        (T, Test_Unknown_PAX_Records'Access, "unknown PAX records");
      Registration.Register_Routine
        (T, Test_PAX_Device_Number_Overrides'Access,
         "PAX device number overrides");
      Registration.Register_Routine
        (T, Test_PAX_Standard_Device_Number_Overrides'Access,
         "standard PAX device number overrides");
      Registration.Register_Routine
        (T, Test_Invalid_PAX_Device_Number_Metadata'Access,
         "invalid PAX device number metadata");
      Registration.Register_Routine
        (T, Test_Writer_PAX_Metadata_Roundtrip'Access,
         "writer PAX metadata roundtrip");
      Registration.Register_Routine
        (T, Test_PAX_Fractional_MTime'Access, "PAX fractional mtime");
      Registration.Register_Routine
        (T, Test_PAX_Negative_Timestamps'Access, "PAX negative timestamps");
      Registration.Register_Routine
        (T, Test_Invalid_PAX_Fractional_MTime'Access,
         "invalid PAX fractional mtime");
      Registration.Register_Routine
        (T, Test_PAX_Numeric_Overflow'Access, "PAX numeric overflow");
      Registration.Register_Routine
        (T, Test_PAX_Signed_Positive_Numerics'Access,
         "PAX signed-positive numerics");
      Registration.Register_Routine
        (T, Test_PAX_Record_Length_Overflow'Access,
         "PAX record length overflow");
      Registration.Register_Routine
        (T, Test_Empty_PAX_Keyword_Rejected'Access,
         "empty PAX keyword rejection");
      Registration.Register_Routine
        (T, Test_Empty_PAX_Path_Metadata_Rejected'Access,
         "empty PAX path metadata rejection");
      Registration.Register_Routine
        (T, Test_Invalid_PAX_Path_Metadata_Rejected'Access,
         "invalid PAX path metadata rejection");
      Registration.Register_Routine
        (T, Test_PAX_Link_Path_Kind_Validation'Access,
         "PAX linkpath kind validation");
      Registration.Register_Routine
        (T, Test_Raw_Hard_Link_Target_Validation'Access,
         "raw hard-link target validation");
      Registration.Register_Routine
        (T, Test_PAX_Link_Path_Supplies_Empty_Header_Target'Access,
         "PAX linkpath supplies empty header target");
      Registration.Register_Routine
        (T, Test_PAX_Size_Ignored_For_Non_File'Access,
         "PAX size ignored for non-file");
      Registration.Register_Routine
        (T, Test_GNU_Long_Name_And_Link'Access, "GNU long name and link");
      Registration.Register_Routine
        (T, Test_Invalid_GNU_Long_Name_Rejected'Access,
         "invalid GNU long name rejection");
      Registration.Register_Routine
        (T, Test_GNU_Long_Link_Kind_Validation'Access,
         "GNU long link kind validation");
      Registration.Register_Routine
        (T, Test_NUL_Link_Metadata_Rejected'Access,
         "NUL link metadata rejection");
      Registration.Register_Routine
        (T, Test_Link_Metadata_For_Non_Link_Rejected'Access,
         "non-link link metadata rejection");
      Registration.Register_Routine
        (T, Test_Global_PAX_Metadata'Access, "global PAX metadata");
      Registration.Register_Routine
        (T, Test_PAX_Owner_Names'Access, "PAX owner names");
      Registration.Register_Routine
        (T, Test_Global_PAX_Metadata_Delete'Access,
         "global PAX metadata deletion");
      Registration.Register_Routine
        (T, Test_Global_PAX_Entry_Keys_Ignored'Access,
         "global PAX entry keys ignored");
      Registration.Register_Routine
        (T, Test_Dangling_Local_Extension_Rejected'Access,
         "dangling local extension rejection");
      Registration.Register_Routine
        (T, Test_Legacy_V7_Header'Access, "legacy V7 header");
      Registration.Register_Routine
        (T, Test_Old_GNU_Magic_Header'Access, "old GNU magic header");
      Registration.Register_Routine
        (T, Test_Contiguous_File_Typeflag'Access,
         "contiguous file typeflag");
      Registration.Register_Routine
        (T, Test_Legacy_V7_Hard_Link'Access, "legacy V7 hard link");
      Registration.Register_Routine
        (T, Test_Hard_Link_With_Data_Blocks'Access,
         "hard link with data blocks");
      Registration.Register_Routine
        (T, Test_PAX_Hard_Link_Size_Data_Blocks'Access,
         "PAX hard link size data blocks");
      Registration.Register_Routine
        (T, Test_Legacy_V7_Directory'Access, "legacy V7 directory");
      Registration.Register_Routine
        (T, Test_Base_256_Size_Header'Access, "base-256 size header");
      Registration.Register_Routine
        (T, Test_Base_256_Metadata_Header'Access,
         "base-256 metadata header");
      Registration.Register_Routine
        (T, Test_Signed_Checksum_Header'Access, "signed checksum header");
      Registration.Register_Routine
        (T, Test_GNU_Sparse_Header_Rejected_Without_Map'Access,
         "GNU sparse header without map rejection");
      Registration.Register_Routine
        (T, Test_GNU_Sparse_PAX_Reconstructed'Access,
         "GNU sparse PAX reconstruction");
      Registration.Register_Routine
        (T, Test_Star_Sparse_PAX_Reconstructed'Access,
         "star sparse PAX reconstruction");
      Registration.Register_Routine
        (T, Test_Old_GNU_Sparse_Header_Reconstructed'Access,
         "old GNU sparse header reconstruction");
      Registration.Register_Routine
        (T, Test_Old_GNU_Sparse_Extension_Reconstructed'Access,
         "old GNU sparse extension reconstruction");
      Registration.Register_Routine
        (T, Test_Multi_Volume_Offsets'Access,
         "GNU multi-volume offsets");
      Registration.Register_Routine
        (T, Test_Incremental_Dump_Listing'Access,
         "GNU incremental dump listing");
      Registration.Register_Routine
        (T, Test_Volume_Label'Access, "volume label");
      Registration.Register_Routine
        (T, Test_Deterministic_Fuzz_Corpus'Access,
         "deterministic fuzz corpus");
   end Register_Tests;
end Tarlib.Reader_Tests;
