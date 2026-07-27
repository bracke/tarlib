with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Hostkit.Process;
with Hostkit;
with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with AUnit.Assertions;
with Interfaces;
with Interfaces.C;
with Interfaces.C.Strings;
with Tarlib.Entries;
with Tarlib.Errors;
with Tarlib.Files;
with Tarlib.Test_Fixtures;
with Tarlib.Test_Outputs;
with Tarlib.Readers;
with Tarlib.Writers;

package body Tarlib.File_Tests is
   use AUnit.Assertions;
   use type Ada.Streams.Stream_Element_Offset;
   use type Ada.Streams.Stream_Element_Array;
   use type Ada.Directories.File_Kind;
   use type Interfaces.C.int;
   use type Interfaces.C.long;
   use type Tarlib.Entries.Entry_Kind;
   use type Tarlib.Errors.Status_Code;

   function C_System
     (Command : Interfaces.C.Strings.chars_ptr) return Interfaces.C.int
     with Import, Convention => C, External_Name => "system";

   function Execute_Command (Command : String) return Interfaces.C.int is
      C_Command : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Command);
      Status    : Interfaces.C.int;
   begin
      Status := C_System (C_Command);
      Interfaces.C.Strings.Free (C_Command);
      return Status;
   exception
      when others =>
         return 1;
   end Execute_Command;

   overriding function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("filesystem convenience APIs");
   end Name;

   procedure Write_File
     (Path   : String;
      Data   : Ada.Streams.Stream_Element_Array;
      Result : out Tarlib.Errors.Status)
   is
      File : Ada.Streams.Stream_IO.File_Type;
   begin
      Ada.Streams.Stream_IO.Create
        (File, Ada.Streams.Stream_IO.Out_File, Path);
      Ada.Streams.Stream_IO.Write (File, Data);
      Ada.Streams.Stream_IO.Close (File);
      Result := Tarlib.Errors.OK;
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         Result := (Code => Tarlib.Errors.Output_Failure);
   end Write_File;

   procedure Read_File
     (Path   : String;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Tarlib.Errors.Status)
   is
      File : Ada.Streams.Stream_IO.File_Type;
   begin
      Last := Data'First - 1;
      Ada.Streams.Stream_IO.Open (File, Ada.Streams.Stream_IO.In_File, Path);
      Ada.Streams.Stream_IO.Read (File, Data, Last);
      Ada.Streams.Stream_IO.Close (File);
      Result := Tarlib.Errors.OK;
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         Last := Data'First - 1;
         Result := (Code => Tarlib.Errors.Input_Failure);
   end Read_File;

   procedure Reset_Tree
     (Path   : String;
      Result : out Tarlib.Errors.Status);

   function Lstat_Mode (Path : String) return Interfaces.C.long;

   procedure Remove_Tree
     (Path   : String;
      Result : out Tarlib.Errors.Status)
   is
      function C_Unlink
        (Path : Interfaces.C.Strings.chars_ptr) return Interfaces.C.int
        with Import, Convention => C, External_Name => "unlink";
      function C_Rmdir
        (Path : Interfaces.C.Strings.chars_ptr) return Interfaces.C.int
        with Import, Convention => C, External_Name => "rmdir";

      Search : Ada.Directories.Search_Type;
      Search_Started : Boolean := False;
      Mode : Interfaces.C.long := Lstat_Mode (Path);
      C_Path : Interfaces.C.Strings.chars_ptr;
      Status : Interfaces.C.int;
   begin
      if Mode >= 0 then
         if (Mode / 4096) mod 16 = 4 then
            Ada.Directories.Start_Search
              (Search, Path, "*",
               [Ada.Directories.Ordinary_File => True,
                Ada.Directories.Directory => True,
                Ada.Directories.Special_File => True]);
            Search_Started := True;
            while Ada.Directories.More_Entries (Search) loop
               declare
                  Item : Ada.Directories.Directory_Entry_Type;
               begin
                  Ada.Directories.Get_Next_Entry (Search, Item);
                  declare
                     Simple : constant String :=
                       Ada.Directories.Simple_Name (Item);
                  begin
                     if Simple /= "." and then Simple /= ".." then
                        Remove_Tree (Ada.Directories.Full_Name (Item), Result);
                        if Result.Code /= Tarlib.Errors.Success then
                           Ada.Directories.End_Search (Search);
                           return;
                        end if;
                     end if;
                  end;
               end;
            end loop;
            Ada.Directories.End_Search (Search);
            Search_Started := False;
            C_Path := Interfaces.C.Strings.New_String (Path);
            Status := C_Rmdir (C_Path);
            Interfaces.C.Strings.Free (C_Path);
         else
            C_Path := Interfaces.C.Strings.New_String (Path);
            Status := C_Unlink (C_Path);
            Interfaces.C.Strings.Free (C_Path);
         end if;

         if Status /= 0 then
            Result := (Code => Tarlib.Errors.Output_Failure);
            return;
         end if;
      end if;
      Result := Tarlib.Errors.OK;
   exception
      when others =>
         if Search_Started then
            Ada.Directories.End_Search (Search);
         end if;
         Result := (Code => Tarlib.Errors.Output_Failure);
   end Remove_Tree;

   procedure Reset_Tree
     (Path   : String;
      Result : out Tarlib.Errors.Status) is
      Status : Interfaces.C.int;
   begin
      Status := Execute_Command ("rm -rf -- " & Path);
      if Status /= 0 then
         Remove_Tree (Path, Result);
      else
         Result := Tarlib.Errors.OK;
      end if;

      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;
      Ada.Directories.Create_Path (Path);
      Result := Tarlib.Errors.OK;
   exception
      when others =>
         Result := (Code => Tarlib.Errors.Output_Failure);
   end Reset_Tree;

   type Stat_Buffer is array (1 .. 256) of Interfaces.C.long
     with Convention => C;

   function Lstat_Mode (Path : String) return Interfaces.C.long is
      function C_Lstat
        (Path : Interfaces.C.Strings.chars_ptr;
         Buf  : access Stat_Buffer) return Interfaces.C.int
        with Import, Convention => C, External_Name => "lstat";

      C_Path : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Path);
      Buffer : aliased Stat_Buffer := [others => 0];
      Status : Interfaces.C.int;
   begin
      Status := C_Lstat (C_Path, Buffer'Access);
      Interfaces.C.Strings.Free (C_Path);
      if Status /= 0 then
         return -1;
      end if;

      return Buffer (4);
   exception
      when others =>
         return -1;
   end Lstat_Mode;

   function File_MTime (Path : String) return Interfaces.C.long is
      function C_Stat
        (Path : Interfaces.C.Strings.chars_ptr;
         Buf  : access Stat_Buffer) return Interfaces.C.int
        with Import, Convention => C, External_Name => "stat";

      C_Path : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Path);
      Buffer : aliased Stat_Buffer := [others => 0];
      Status : Interfaces.C.int;
   begin
      Status := C_Stat (C_Path, Buffer'Access);
      Interfaces.C.Strings.Free (C_Path);
      if Status /= 0 then
         return -1;
      end if;

      return Buffer (12);
   exception
      when others =>
         return -1;
   end File_MTime;

   procedure Test_File_Archive_Roundtrip
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Root         : constant String := "/tmp/tarlib-files-test";
      Input_Dir    : constant String := Root & "/input";
      Nested_Dir   : constant String := Input_Dir & "/dir";
      Output_Dir   : constant String := Root & "/output";
      Source_Path  : constant String := Nested_Dir & "/source.bin";
      Archive_Path : constant String := Root & "/archive.tar";
      Extracted    : constant String := Output_Dir & "/dir/dir/source.bin";
      Payload      : constant Ada.Streams.Stream_Element_Array :=
        [Character'Pos ('f'), Character'Pos ('i'), Character'Pos ('l'),
         Character'Pos ('e'), Character'Pos ('s')];
      Read_Back    : Ada.Streams.Stream_Element_Array (1 .. Payload'Length);
      Last         : Ada.Streams.Stream_Element_Offset;
      Result       : Tarlib.Errors.Status;
      Sink         : Tarlib.Files.File_Output_Sink;
      Source       : Tarlib.Files.File_Input_Source;
      Writer       : Tarlib.Writers.Writer;
      Reader       : Tarlib.Readers.Reader;
   begin
      Reset_Tree (Root, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reset root");
      Ada.Directories.Create_Path (Nested_Dir);
      Write_File (Source_Path, Payload, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write source");

      Tarlib.Files.Create_Write (Sink, Archive_Path, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "create archive");
      Tarlib.Writers.Initialize (Writer, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "writer initialize");
      Tarlib.Files.Add_Tree (Writer, Input_Dir, "dir", Result);
      Assert (Result.Code = Tarlib.Errors.Success, "add tree");
      Tarlib.Writers.Finish (Writer, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "finish archive");
      Tarlib.Files.Close (Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "close archive");

      Tarlib.Files.Open_Read (Source, Archive_Path, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "open archive");
      Tarlib.Readers.Initialize (Reader, Source, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");
      Tarlib.Files.Extract_All (Reader, Output_Dir, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "extract archive");
      Tarlib.Files.Close (Source, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "close source");

      Read_File (Extracted, Read_Back, Last, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "read extracted");
      Assert (Last = Read_Back'Last, "extracted length");
      Assert (Read_Back = Payload, "extracted payload");
   end Test_File_Archive_Roundtrip;

   --  The ACL path had no coverage at all, which is how it went from a shell
   --  command to an argument vector without anyone noticing that the spawn
   --  underneath does not search PATH. It needs a host with setfacl and a
   --  filesystem that takes an ACL, so it says what it skipped rather than
   --  passing quietly.
   procedure Test_Native_ACL_Applied
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      --  A space in the path: the filter this replaced rejected one, and
      --  reported a legal path as invalid metadata.
      Root       : constant String := "/tmp/tarlib acl test";
      Output_Dir : constant String := Root & "/output";
      Probe      : constant String := Root & "/probe.bin";
      ACL_Text   : constant String := "u::rwx";

      Setfacl    : constant String := Hostkit.Process.Locate ("setfacl");

      function Filesystem_Takes_ACLs return Boolean is
         Items  : Hostkit.String_Vectors.Vector;
         Status : Integer;
         Ran    : Boolean;
         File   : Ada.Streams.Stream_IO.File_Type;
      begin
         Ada.Streams.Stream_IO.Create
           (File, Ada.Streams.Stream_IO.Out_File, Probe);
         Ada.Streams.Stream_IO.Close (File);
         Items.Append (Ada.Strings.Unbounded.To_Unbounded_String ("-m"));
         Items.Append (Ada.Strings.Unbounded.To_Unbounded_String (ACL_Text));
         Items.Append (Ada.Strings.Unbounded.To_Unbounded_String (Probe));
         Ran := Hostkit.Process.Run (Setfacl, Items, Status);
         return Ran and then Status = 0;
      exception
         when others =>
            return False;
      end Filesystem_Takes_ACLs;

      Payload  : constant Ada.Streams.Stream_Element_Array :=
        [Character'Pos ('a'), Character'Pos ('c'), Character'Pos ('l')];
      Result   : Tarlib.Errors.Status;
      Sink     : aliased Tarlib.Test_Outputs.Memory_Sink;
      Writer   : Tarlib.Writers.Writer;
      Reader   : Tarlib.Readers.Reader;
      Metadata : Tarlib.Entries.Metadata :=
        Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File);
      Options  : constant Tarlib.Files.Extraction_Options :=
        (Unsupported_Entries => Tarlib.Files.Skip_Unsupported,
         Apply_Permissions   => True,
         Apply_Timestamps    => False,
         Apply_Ownership     => False,
         Create_Special_Entries => False,
         Extract_GNU_Metadata => True,
         Device_Layout => Tarlib.Files.Native_Device_Layout,
         Apply_Extended_Attributes => False,
         Apply_ACLs => False,
         Apply_File_Flags => False,
         Apply_Native_ACLs => True,
         Apply_Native_File_Flags => False);
   begin
      Reset_Tree (Root, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reset root");

      if Setfacl = "" then
         Ada.Text_IO.Put_Line ("   (skipped: no setfacl on this host)");
         return;
      elsif not Filesystem_Takes_ACLs then
         Ada.Text_IO.Put_Line
           ("   (skipped: this filesystem will not take an ACL)");
         return;
      end if;

      Metadata.Mode := 8#0600#;
      Tarlib.Writers.Initialize (Writer, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "writer initialize");
      Tarlib.Writers.Add_Extended_Record
        (Writer, "SCHILY.acl.access", ACL_Text, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "add ACL record");
      Tarlib.Writers.Begin_Entry
        (Writer, "file.bin", Tarlib.Entries.Regular_File,
         Tarlib.Byte_Count (Payload'Length), Metadata, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "begin file");
      Tarlib.Writers.Write (Writer, Payload, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write payload");
      Tarlib.Writers.End_Entry (Writer, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "end file");
      Tarlib.Writers.Finish (Writer, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "finish archive");

      Tarlib.Test_Outputs.Rewind (Sink);
      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");

      --  Success here means setfacl was found and returned 0. Before the tool
      --  was resolved through PATH this failed, and failed as a status the
      --  caller could not tell from setfacl refusing the ACL.
      Tarlib.Files.Extract_All (Reader, Output_Dir, Options, Result);
      Assert
        (Result.Code = Tarlib.Errors.Success,
         "extraction applies a native ACL under a path holding a space");
   end Test_Native_ACL_Applied;

   procedure Test_Extraction_Options
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Root       : constant String := "/tmp/tarlib-files-options-test-2";
      Output_Dir : constant String := Root & "/output";
      Extracted  : constant String := Output_Dir & "/file.bin";
      Payload    : constant Ada.Streams.Stream_Element_Array :=
        [Character'Pos ('m'), Character'Pos ('o'), Character'Pos ('d'),
         Character'Pos ('e')];
      Read_Back  : Ada.Streams.Stream_Element_Array (1 .. Payload'Length);
      Last       : Ada.Streams.Stream_Element_Offset;
      Result     : Tarlib.Errors.Status;
      Sink       : aliased Tarlib.Test_Outputs.Memory_Sink;
      Writer     : Tarlib.Writers.Writer;
      Reader     : Tarlib.Readers.Reader;
      Metadata   : Tarlib.Entries.Metadata :=
        Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File);
      Options    : constant Tarlib.Files.Extraction_Options :=
        (Unsupported_Entries => Tarlib.Files.Skip_Unsupported,
         Apply_Permissions   => True,
         Apply_Timestamps    => False,
         Apply_Ownership     => False,
         Create_Special_Entries => False,
         Extract_GNU_Metadata => False,
         Device_Layout => Tarlib.Files.Native_Device_Layout,
         Apply_Extended_Attributes => False,
         Apply_ACLs => False,
         Apply_File_Flags => False,
         Apply_Native_ACLs => False,
         Apply_Native_File_Flags => False);
   begin
      Metadata.Mode := 8#0600#;
      Reset_Tree (Root, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reset root");

      Tarlib.Writers.Initialize (Writer, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "writer initialize");
      Tarlib.Writers.Add_FIFO (Writer, "pipe", Result);
      Assert (Result.Code = Tarlib.Errors.Success, "add unsupported FIFO");
      Tarlib.Writers.Begin_Entry
        (Writer, "file.bin", Tarlib.Entries.Regular_File,
         Tarlib.Byte_Count (Payload'Length), Metadata, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "begin file");
      Tarlib.Writers.Write (Writer, Payload, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write payload");
      Tarlib.Writers.End_Entry (Writer, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "end file");
      Tarlib.Writers.Finish (Writer, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "finish archive");

      Tarlib.Test_Outputs.Rewind (Sink);
      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");
      Tarlib.Files.Extract_All (Reader, Output_Dir, Options, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "extract with options");

      Read_File (Extracted, Read_Back, Last, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "read extracted");
      Assert (Last = Read_Back'Last, "extracted length");
      Assert (Read_Back = Payload, "extracted payload");
   end Test_Extraction_Options;

   procedure Test_POSIX_Link_Extraction
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Root       : constant String := "/tmp/tarlib-files-links-test";
      Output_Dir : constant String := Root & "/output";
      Original   : constant String := Output_Dir & "/dir/file.txt";
      Hard_Link  : constant String := Output_Dir & "/dir/hard.txt";
      Sym_Link   : constant String := Output_Dir & "/dir/sym.txt";
      Payload    : constant Ada.Streams.Stream_Element_Array :=
        [Character'Pos ('l'), Character'Pos ('i'), Character'Pos ('n'),
         Character'Pos ('k')];
      Read_Back  : Ada.Streams.Stream_Element_Array (1 .. Payload'Length);
      Last       : Ada.Streams.Stream_Element_Offset;
      Result     : Tarlib.Errors.Status;
      Sink       : aliased Tarlib.Test_Outputs.Memory_Sink;
      Writer     : Tarlib.Writers.Writer;
      Reader     : Tarlib.Readers.Reader;
      Options    : constant Tarlib.Files.Extraction_Options :=
        (Unsupported_Entries => Tarlib.Files.Reject_Unsupported,
         Apply_Permissions   => False,
         Apply_Timestamps    => False,
         Apply_Ownership     => False,
         Create_Special_Entries => False,
         Extract_GNU_Metadata => False,
         Device_Layout => Tarlib.Files.Native_Device_Layout,
         Apply_Extended_Attributes => False,
         Apply_ACLs => False,
         Apply_File_Flags => False,
         Apply_Native_ACLs => False,
         Apply_Native_File_Flags => False);
   begin
      Reset_Tree (Root, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reset root");

      Tarlib.Writers.Initialize (Writer, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "writer initialize");
      Tarlib.Writers.Add_Directory (Writer, "dir/", Result);
      Assert (Result.Code = Tarlib.Errors.Success, "add directory");
      Tarlib.Writers.Begin_File
        (Writer, "dir/file.txt", Tarlib.Byte_Count (Payload'Length), Result);
      Assert (Result.Code = Tarlib.Errors.Success, "begin file");
      Tarlib.Writers.Write (Writer, Payload, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write payload");
      Tarlib.Writers.End_Entry (Writer, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "end file");
      Tarlib.Writers.Add_Hard_Link
        (Writer, "dir/hard.txt", "dir/file.txt", Result);
      Assert (Result.Code = Tarlib.Errors.Success, "add hard link");
      Tarlib.Writers.Add_Symbolic_Link
        (Writer, "dir/sym.txt", "file.txt", Result);
      Assert (Result.Code = Tarlib.Errors.Success, "add symbolic link");
      Tarlib.Writers.Finish (Writer, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "finish archive");

      Tarlib.Test_Outputs.Rewind (Sink);
      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");
      Tarlib.Files.Extract_All (Reader, Output_Dir, Options, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "extract links");

      Read_File (Original, Read_Back, Last, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "read original");
      Assert (Last = Read_Back'Last and then Read_Back = Payload, "original");
      Read_File (Hard_Link, Read_Back, Last, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "read hard link");
      Assert (Last = Read_Back'Last and then Read_Back = Payload, "hard link");
      Read_File (Sym_Link, Read_Back, Last, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "read symlink");
      Assert (Last = Read_Back'Last and then Read_Back = Payload, "symlink");
   end Test_POSIX_Link_Extraction;

   procedure Test_POSIX_Special_And_Timestamp_Extraction
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Root       : constant String := "/tmp/tarlib-files-special-test";
      Output_Dir : constant String := Root & "/output";
      FIFO_Path  : constant String := Output_Dir & "/pipe";
      File_Path  : constant String := Output_Dir & "/dated.txt";
      Payload    : constant Ada.Streams.Stream_Element_Array :=
        [Character'Pos ('t')];
      Result     : Tarlib.Errors.Status;
      Sink       : aliased Tarlib.Test_Outputs.Memory_Sink;
      Writer     : Tarlib.Writers.Writer;
      Reader     : Tarlib.Readers.Reader;
      Metadata   : Tarlib.Entries.Metadata :=
        Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File);
      FIFO_Meta  : Tarlib.Entries.Metadata :=
        Tarlib.Entries.Default_Metadata (Tarlib.Entries.FIFO);
      Options    : constant Tarlib.Files.Extraction_Options :=
        (Unsupported_Entries => Tarlib.Files.Reject_Unsupported,
         Apply_Permissions   => True,
         Apply_Timestamps    => True,
         Apply_Ownership     => False,
         Create_Special_Entries => True,
         Extract_GNU_Metadata => False,
         Device_Layout => Tarlib.Files.Native_Device_Layout,
         Apply_Extended_Attributes => False,
         Apply_ACLs => False,
         Apply_File_Flags => False,
         Apply_Native_ACLs => False,
         Apply_Native_File_Flags => False);
      FIFO_Mode  : Interfaces.C.long;
   begin
      Metadata.MTime := 1_234_567_890;
      Metadata.ATime := 1_234_567_800;
      FIFO_Meta.Mode := 8#0600#;

      Reset_Tree (Root, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reset root");

      Tarlib.Writers.Initialize (Writer, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "writer initialize");
      Tarlib.Writers.Add_Special
        (Writer, "pipe", Tarlib.Entries.FIFO, Tarlib.Entries.No_Device,
         FIFO_Meta, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "add FIFO");
      Tarlib.Writers.Begin_Entry
        (Writer, "dated.txt", Tarlib.Entries.Regular_File,
         Tarlib.Byte_Count (Payload'Length), Metadata, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "begin dated file");
      Tarlib.Writers.Write (Writer, Payload, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write dated payload");
      Tarlib.Writers.End_Entry (Writer, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "end dated file");
      Tarlib.Writers.Finish (Writer, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "finish archive");

      Tarlib.Test_Outputs.Rewind (Sink);
      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");
      Tarlib.Files.Extract_All (Reader, Output_Dir, Options, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "extract special");

      FIFO_Mode := Lstat_Mode (FIFO_Path);
      Assert (FIFO_Mode >= 0, "FIFO stat succeeds");
      Assert ((FIFO_Mode / 4096) mod 16 = 1, "FIFO node created");
      Assert (File_MTime (File_Path) = 1_234_567_890, "mtime applied");
   end Test_POSIX_Special_And_Timestamp_Extraction;

   procedure Test_GNU_Metadata_Extraction_Options
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Root       : constant String := "/tmp/tarlib-files-gnu-meta-test";
      Reject_Dir : constant String := Root & "/reject";
      Skip_Dir   : constant String := Root & "/skip";
      Extract_Dir : constant String := Root & "/extract";
      Result     : Tarlib.Errors.Status;
      Sink       : aliased Tarlib.Test_Outputs.Memory_Sink;
      Writer     : Tarlib.Writers.Writer;
      Reject_Reader : Tarlib.Readers.Reader;
      Skip_Reader   : Tarlib.Readers.Reader;
      Extract_Reader : Tarlib.Readers.Reader;
      Multi_Data : constant Ada.Streams.Stream_Element_Array :=
        [Character'Pos ('p')];
      Dump_Data  : constant Ada.Streams.Stream_Element_Array :=
        [Character'Pos ('Y'), Character'Pos ('d'), 0, 0];
      Reject_Options : constant Tarlib.Files.Extraction_Options :=
        (Unsupported_Entries => Tarlib.Files.Reject_Unsupported,
         Apply_Permissions   => False,
         Apply_Timestamps    => False,
         Apply_Ownership     => False,
         Create_Special_Entries => False,
         Extract_GNU_Metadata => False,
         Device_Layout => Tarlib.Files.Native_Device_Layout,
         Apply_Extended_Attributes => False,
         Apply_ACLs => False,
         Apply_File_Flags => False,
         Apply_Native_ACLs => False,
         Apply_Native_File_Flags => False);
      Skip_Options : constant Tarlib.Files.Extraction_Options :=
        (Unsupported_Entries => Tarlib.Files.Skip_Unsupported,
         Apply_Permissions   => False,
         Apply_Timestamps    => False,
         Apply_Ownership     => False,
         Create_Special_Entries => False,
         Extract_GNU_Metadata => False,
         Device_Layout => Tarlib.Files.Native_Device_Layout,
         Apply_Extended_Attributes => False,
         Apply_ACLs => False,
         Apply_File_Flags => False,
         Apply_Native_ACLs => False,
         Apply_Native_File_Flags => False);
      Extract_Options : constant Tarlib.Files.Extraction_Options :=
        (Unsupported_Entries => Tarlib.Files.Reject_Unsupported,
         Apply_Permissions   => False,
         Apply_Timestamps    => False,
         Apply_Ownership     => False,
         Create_Special_Entries => False,
         Extract_GNU_Metadata => True,
         Device_Layout => Tarlib.Files.Native_Device_Layout,
         Apply_Extended_Attributes => False,
         Apply_ACLs => False,
         Apply_File_Flags => False,
         Apply_Native_ACLs => False,
         Apply_Native_File_Flags => False);
      Multi_Read : Ada.Streams.Stream_Element_Array (1 .. 1);
      Listing_Read : Ada.Streams.Stream_Element_Array (1 .. 4);
      Label_Read : Ada.Streams.Stream_Element_Array (1 .. 14);
      Last : Ada.Streams.Stream_Element_Offset;
   begin
      Reset_Tree (Root, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reset root");
      Ada.Directories.Create_Path (Reject_Dir);
      Ada.Directories.Create_Path (Skip_Dir);
      Ada.Directories.Create_Path (Extract_Dir);

      Tarlib.Writers.Initialize (Writer, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "writer initialize");
      Tarlib.Writers.Begin_Entry
        (Writer, "continued.bin", Tarlib.Entries.Multi_Volume,
         Tarlib.Byte_Count (Multi_Data'Length),
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Multi_Volume),
         Result);
      Assert (Result.Code = Tarlib.Errors.Success, "multi entry");
      Tarlib.Writers.Write (Writer, Multi_Data, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "multi data");
      Tarlib.Writers.End_Entry (Writer, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "multi end");
      Tarlib.Writers.Begin_Entry
        (Writer, "dumpdir", Tarlib.Entries.Incremental_Dump,
         Tarlib.Byte_Count (Dump_Data'Length),
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Incremental_Dump),
         Result);
      Assert (Result.Code = Tarlib.Errors.Success, "dump entry");
      Tarlib.Writers.Write (Writer, Dump_Data, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "dump data");
      Tarlib.Writers.End_Entry (Writer, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "dump end");
      Tarlib.Writers.Begin_Entry
        (Writer, "TARLIB_VOLUME", Tarlib.Entries.Volume_Label, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Volume_Label),
         Result);
      Assert (Result.Code = Tarlib.Errors.Success, "volume entry");
      Tarlib.Writers.End_Entry (Writer, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "volume end");
      Tarlib.Writers.Finish (Writer, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "finish");

      Tarlib.Test_Outputs.Rewind (Sink);
      Tarlib.Readers.Initialize (Reject_Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reject reader");
      Tarlib.Files.Extract_All
        (Reject_Reader, Reject_Dir, Reject_Options, Result);
      Assert
        (Result.Code = Tarlib.Errors.Invalid_Entry_Kind,
         "GNU metadata entries rejected by default");

      Tarlib.Test_Outputs.Rewind (Sink);
      Tarlib.Readers.Initialize (Skip_Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "skip reader");
      Tarlib.Files.Extract_All
        (Skip_Reader, Skip_Dir, Skip_Options, Result);
      Assert
        (Result.Code = Tarlib.Errors.Success,
         "GNU metadata entries skipped when requested");
      Assert
        (not Ada.Directories.Exists (Skip_Dir & "/continued.bin"),
         "multi-volume not extracted as file");
      Assert
        (not Ada.Directories.Exists (Skip_Dir & "/dumpdir"),
         "incremental dump not extracted as directory");

      Tarlib.Test_Outputs.Rewind (Sink);
      Tarlib.Readers.Initialize (Extract_Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "extract reader");
      Tarlib.Files.Extract_All
        (Extract_Reader, Extract_Dir, Extract_Options, Result);
      Assert
        (Result.Code = Tarlib.Errors.Success,
         "GNU metadata entries materialized when requested");
      Read_File (Extract_Dir & "/continued.bin", Multi_Read, Last, Result);
      Assert
        (Result.Code = Tarlib.Errors.Success
         and then Last = 1
         and then Multi_Read = Multi_Data,
         "multi-volume materialized");
      Read_File
        (Extract_Dir & "/dumpdir/.gnu-incremental-listing",
         Listing_Read, Last, Result);
      Assert
        (Result.Code = Tarlib.Errors.Success
         and then Last = 4
         and then Listing_Read =
           [Character'Pos ('Y'), Character'Pos (' '),
            Character'Pos ('d'), Character'Pos (Character'Val (10))],
         "incremental listing materialized");
      Read_File
        (Extract_Dir & "/.tar-volume-label", Label_Read, Last, Result);
      Assert
        (Result.Code = Tarlib.Errors.Success
         and then Last = 14,
         "volume label materialized");
   end Test_GNU_Metadata_Extraction_Options;

   procedure Test_Multi_Volume_Reassembly
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Root        : constant String := "/tmp/tarlib-reassemble-test";
      Volume_1    : constant String := Root & "/part1.tar";
      Volume_2    : constant String := Root & "/part2.tar";
      Output_Path : constant String := Root & "/out.bin";
      Result      : Tarlib.Errors.Status;
      Sink        : Tarlib.Files.File_Output_Sink;
      Writer_1    : Tarlib.Writers.Writer;
      Writer_2    : Tarlib.Writers.Writer;
      Part_1      : constant Ada.Streams.Stream_Element_Array :=
        [Character'Pos ('a'), Character'Pos ('b'), Character'Pos ('c')];
      Part_2      : constant Ada.Streams.Stream_Element_Array :=
        [Character'Pos ('d'), Character'Pos ('e')];
      Read_Back   : Ada.Streams.Stream_Element_Array (1 .. 5);
      Last        : Ada.Streams.Stream_Element_Offset;
   begin
      Reset_Tree (Root, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reset root");

      Tarlib.Files.Create_Write (Sink, Volume_1, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "create volume 1");
      Tarlib.Writers.Initialize (Writer_1, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "writer 1");
      Tarlib.Writers.Begin_File (Writer_1, "file.bin", 3, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "begin file");
      Tarlib.Writers.Write (Writer_1, Part_1, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write part 1");
      Tarlib.Writers.End_Entry (Writer_1, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "end part 1");
      Tarlib.Writers.Finish (Writer_1, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "finish volume 1");
      Tarlib.Files.Close (Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "close volume 1");

      Tarlib.Files.Create_Write (Sink, Volume_2, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "create volume 2");
      Tarlib.Writers.Initialize (Writer_2, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "writer 2");
      Tarlib.Writers.Add_Extended_Record
        (Writer_2, "GNU.volume.offset", "3", Result);
      Assert (Result.Code = Tarlib.Errors.Success, "offset PAX");
      Tarlib.Writers.Begin_Entry
        (Writer_2, "file.bin", Tarlib.Entries.Multi_Volume, 2,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Multi_Volume),
         Result);
      Assert (Result.Code = Tarlib.Errors.Success, "begin continuation");
      Tarlib.Writers.Write (Writer_2, Part_2, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write part 2");
      Tarlib.Writers.End_Entry (Writer_2, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "end part 2");
      Tarlib.Writers.Finish (Writer_2, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "finish volume 2");
      Tarlib.Files.Close (Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "close volume 2");

      Tarlib.Files.Reassemble_Multi_Volume_File
        (Volume_1 & Character'Val (10) & Volume_2, Output_Path, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reassemble");
      Read_File (Output_Path, Read_Back, Last, Result);
      Assert
        (Result.Code = Tarlib.Errors.Success
         and then Last = 5
         and then Read_Back =
           [Character'Pos ('a'), Character'Pos ('b'), Character'Pos ('c'),
            Character'Pos ('d'), Character'Pos ('e')],
         "reassembled bytes");
   end Test_Multi_Volume_Reassembly;

   procedure Test_Vendor_Metadata_Extraction
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Root       : constant String := "/tmp/tarlib-vendor-meta-test";
      Output_Dir : constant String := Root & "/out";
      Result     : Tarlib.Errors.Status;
      Sink       : aliased Tarlib.Test_Outputs.Memory_Sink;
      Writer     : Tarlib.Writers.Writer;
      Reader     : Tarlib.Readers.Reader;
      Payload    : constant Ada.Streams.Stream_Element_Array :=
        [Character'Pos ('x')];
      Options    : constant Tarlib.Files.Extraction_Options :=
        (Unsupported_Entries => Tarlib.Files.Reject_Unsupported,
         Apply_Permissions   => False,
         Apply_Timestamps    => False,
         Apply_Ownership     => False,
         Create_Special_Entries => False,
         Extract_GNU_Metadata => False,
         Device_Layout => Tarlib.Files.Native_Device_Layout,
         Apply_Extended_Attributes => False,
         Apply_ACLs => True,
         Apply_File_Flags => True,
         Apply_Native_ACLs => False,
         Apply_Native_File_Flags => False);
      ACL_Read   : Ada.Streams.Stream_Element_Array (1 .. 10);
      Flag_Read  : Ada.Streams.Stream_Element_Array (1 .. 7);
      Last       : Ada.Streams.Stream_Element_Offset;
   begin
      Reset_Tree (Root, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reset root");

      Tarlib.Writers.Initialize (Writer, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "writer initialize");
      Tarlib.Writers.Add_Extended_Record
        (Writer, "SCHILY.acl.access", "user::rw-", Result);
      Assert (Result.Code = Tarlib.Errors.Success, "acl PAX");
      Tarlib.Writers.Add_Extended_Record
        (Writer, "LIBARCHIVE.fflags", "nodump", Result);
      Assert (Result.Code = Tarlib.Errors.Success, "flags PAX");
      Tarlib.Writers.Begin_File (Writer, "file.txt", 1, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "begin file");
      Tarlib.Writers.Write (Writer, Payload, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write payload");
      Tarlib.Writers.End_Entry (Writer, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "end file");
      Tarlib.Writers.Finish (Writer, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "finish");

      Tarlib.Test_Outputs.Rewind (Sink);
      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");
      Tarlib.Files.Extract_All (Reader, Output_Dir, Options, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "extract");
      Read_File
        (Output_Dir & "/file.txt.schily-acl-access", ACL_Read, Last, Result);
      Assert
        (Result.Code = Tarlib.Errors.Success
         and then Last = 10
         and then ACL_Read =
           [Character'Pos ('u'), Character'Pos ('s'),
            Character'Pos ('e'), Character'Pos ('r'),
            Character'Pos (':'), Character'Pos (':'),
            Character'Pos ('r'), Character'Pos ('w'),
            Character'Pos ('-'), Character'Pos (Character'Val (10))],
         "ACL sidecar");
      Read_File
        (Output_Dir & "/file.txt.libarchive-fflags", Flag_Read, Last, Result);
      Assert
        (Result.Code = Tarlib.Errors.Success
         and then Last = 7
         and then Flag_Read =
           [Character'Pos ('n'), Character'Pos ('o'), Character'Pos ('d'),
            Character'Pos ('u'), Character'Pos ('m'), Character'Pos ('p'),
            Character'Pos (Character'Val (10))],
         "flags sidecar");
   end Test_Vendor_Metadata_Extraction;

   procedure Test_Tool_Corpus_Archives
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Root        : constant String := "/tmp/tarlib-tool-corpus-test";
      Input_Dir   : constant String := Root & "/input";
      Payload     : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes ("tool archive payload");
      Result      : Tarlib.Errors.Status;
      Checked     : Natural := 0;

      procedure Check_Archive (Label : String; Command : String) is
         Archive_Path : constant String := Root & "/" & Label & ".tar";
         Source       : aliased Tarlib.Files.File_Input_Source;
         Reader       : Tarlib.Readers.Reader;
         Info         : Tarlib.Readers.Entry_Info;
         Has_Entry    : Boolean;
         Buffer       : Ada.Streams.Stream_Element_Array
           (1 .. Ada.Streams.Stream_Element_Offset (Payload'Length));
         Last         : Ada.Streams.Stream_Element_Offset;
      begin
         Assert
           (Execute_Command (Command & " -cf " & Archive_Path
              & " -C " & Input_Dir & " file.txt") = 0,
            Label & " created archive");

         Tarlib.Files.Open_Read (Source, Archive_Path, Result);
         Assert (Result.Code = Tarlib.Errors.Success, Label & " open");
         Tarlib.Readers.Initialize (Reader, Source, Result);
         Assert (Result.Code = Tarlib.Errors.Success, Label & " reader");
         Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
         Assert
           (Result.Code = Tarlib.Errors.Success and then Has_Entry,
            Label & " entry");
         Assert (Tarlib.Readers.Path (Info) = "file.txt", Label & " path");
         Assert
           (Tarlib.Readers.Kind (Info) = Tarlib.Entries.Regular_File,
            Label & " kind");
         Tarlib.Readers.Read (Reader, Buffer, Last, Result);
         Assert
           (Result.Code = Tarlib.Errors.Success
            and then Last = Ada.Streams.Stream_Element_Offset (Payload'Length)
            and then Buffer = Payload,
            Label & " payload");
         Tarlib.Files.Close (Source, Result);
         Assert (Result.Code = Tarlib.Errors.Success, Label & " close");
         Checked := Checked + 1;
      end Check_Archive;
   begin
      Reset_Tree (Root, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reset root");
      Ada.Directories.Create_Path (Input_Dir);
      Write_File (Input_Dir & "/file.txt", Payload, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "write corpus file");

      if Execute_Command ("command -v tar >/dev/null 2>&1") = 0 then
         Check_Archive ("gnu-tar", "tar");
      end if;

      if Execute_Command ("command -v busybox >/dev/null 2>&1") = 0 then
         Check_Archive ("busybox-tar", "busybox tar");
      end if;

      Assert (Checked > 0, "at least one external tar corpus tool available");
   end Test_Tool_Corpus_Archives;

   overriding procedure Register_Tests (T : in out Test_Case) is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine
        (T, Test_File_Archive_Roundtrip'Access, "file archive roundtrip");
      Registration.Register_Routine
        (T, Test_Extraction_Options'Access, "extraction options");
      AUnit.Test_Cases.Registration.Register_Routine
        (T, Test_Native_ACL_Applied'Access, "native ACL applied on extraction");
      Registration.Register_Routine
        (T, Test_POSIX_Link_Extraction'Access, "POSIX link extraction");
      Registration.Register_Routine
        (T, Test_POSIX_Special_And_Timestamp_Extraction'Access,
         "POSIX special and timestamp extraction");
      Registration.Register_Routine
        (T, Test_GNU_Metadata_Extraction_Options'Access,
         "GNU metadata extraction options");
      Registration.Register_Routine
        (T, Test_Multi_Volume_Reassembly'Access,
         "multi-volume reassembly");
      Registration.Register_Routine
        (T, Test_Vendor_Metadata_Extraction'Access,
         "vendor metadata extraction");
      Registration.Register_Routine
        (T, Test_Tool_Corpus_Archives'Access,
         "external tool corpus archives");
   end Register_Tests;
end Tarlib.File_Tests;
