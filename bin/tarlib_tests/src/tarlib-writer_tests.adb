with Ada.Streams;
with AUnit.Assertions;
with Tarlib.Entries;
with Tarlib.Errors;
with Tarlib.Readers;
with Tarlib.Test_Fixtures;
with Tarlib.Test_Outputs;
with Tarlib.Writers;

package body Tarlib.Writer_Tests is
   use AUnit.Assertions;
   use type Ada.Streams.Stream_Element_Offset;
   use type Ada.Streams.Stream_Element;
   use type Ada.Streams.Stream_Element_Array;
   use type Tarlib.Byte_Count;
   use type Tarlib.Entries.Entry_Kind;
   use type Tarlib.Entries.Timestamp;
   use type Tarlib.Errors.Status_Code;
   use type Tarlib.Writers.Writer_State;

   overriding function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("writer state machine");
   end Name;

   procedure Test_Initialization (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Sink   : aliased Tarlib.Test_Outputs.Memory_Sink;
      Writer : Tarlib.Writers.Writer;
      Result : Tarlib.Errors.Status;
   begin
      Assert
        (Tarlib.Writers.State (Writer) = Tarlib.Writers.Uninitialized,
         "initial state");
      Tarlib.Writers.Initialize (Writer, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "initialize succeeds");
      Assert (Tarlib.Writers.State (Writer) = Tarlib.Writers.Ready, "ready");
      Tarlib.Writers.Initialize (Writer, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Invalid_State, "double initialize rejected");
   end Test_Initialization;

   procedure Test_Invalid_Sequences
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Sink   : aliased Tarlib.Test_Outputs.Memory_Sink;
      Writer : Tarlib.Writers.Writer;
      Result : Tarlib.Errors.Status;
      Bytes  : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes ("abc");

      procedure Check_Generic_Entry_Rejected
        (Kind    : Tarlib.Entries.Entry_Kind;
         Message : String)
      is
      begin
         Tarlib.Writers.Begin_Entry
           (Writer, "generic", Kind, 0,
            Tarlib.Entries.Default_Metadata (Kind), Result);
         Assert
           (Result.Code = Tarlib.Errors.Invalid_Entry_Kind,
            Message & " rejected");
         Assert
           (Tarlib.Writers.State (Writer) = Tarlib.Writers.Ready,
            Message & " leaves writer ready");
      end Check_Generic_Entry_Rejected;
   begin
      Tarlib.Writers.Write (Writer, Bytes, Result);
      Assert (Result.Code = Tarlib.Errors.Invalid_State, "write before init rejected");
      Tarlib.Writers.Initialize (Writer, Sink, Result);
      Tarlib.Writers.Write (Writer, Bytes, Result);
      Assert (Result.Code = Tarlib.Errors.Invalid_State, "write outside entry rejected");
      Check_Generic_Entry_Rejected
        (Tarlib.Entries.Symbolic_Link, "generic symbolic link entry");
      Check_Generic_Entry_Rejected
        (Tarlib.Entries.Character_Device, "generic character device entry");
      Check_Generic_Entry_Rejected
        (Tarlib.Entries.PAX_Extended_Header, "generic PAX entry");
      Check_Generic_Entry_Rejected
        (Tarlib.Entries.GNU_Sparse, "generic GNU sparse entry");
      Assert (Tarlib.Test_Outputs.Length (Sink) = 0, "no invalid headers");
      Tarlib.Writers.Begin_File (Writer, "a", 3, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "begin file succeeds");
      Tarlib.Writers.Begin_File (Writer, "b", 0, Result);
      Assert (Result.Code = Tarlib.Errors.Invalid_State, "begin while active rejected");
      Tarlib.Writers.Write
        (Writer, Tarlib.Test_Fixtures.To_Bytes ("abcd"), Result);
      Assert (Result.Code = Tarlib.Errors.Too_Much_Entry_Data, "too much rejected");
      Tarlib.Writers.End_Entry (Writer, Result);
      Assert (Result.Code = Tarlib.Errors.Too_Little_Entry_Data, "too little rejected");
   end Test_Invalid_Sequences;

   procedure Test_Exact_Completion
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Sink   : aliased Tarlib.Test_Outputs.Memory_Sink;
      Writer : Tarlib.Writers.Writer;
      Result : Tarlib.Errors.Status;
   begin
      Tarlib.Writers.Initialize (Writer, Sink, Result);
      Tarlib.Writers.Begin_File (Writer, "a", 3, Result);
      Tarlib.Writers.Write (Writer, Tarlib.Test_Fixtures.To_Bytes ("a"), Result);
      Assert (Result.Code = Tarlib.Errors.Success, "first chunk succeeds");
      Tarlib.Writers.Write (Writer, Tarlib.Test_Fixtures.To_Bytes ("bc"), Result);
      Assert (Result.Code = Tarlib.Errors.Success, "second chunk succeeds");
      Tarlib.Writers.End_Entry (Writer, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "end succeeds at exact size");
      Assert (Tarlib.Writers.State (Writer) = Tarlib.Writers.Ready, "ready after end");
   end Test_Exact_Completion;

   procedure Test_Directory_Write_Rejected
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Sink   : aliased Tarlib.Test_Outputs.Memory_Sink;
      Writer : Tarlib.Writers.Writer;
      Result : Tarlib.Errors.Status;
   begin
      Tarlib.Writers.Initialize (Writer, Sink, Result);
      Tarlib.Writers.Begin_Entry
        (Writer, "dir/", Tarlib.Entries.Directory, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Directory), Result);
      Assert (Result.Code = Tarlib.Errors.Success, "directory begin succeeds");
      Tarlib.Writers.Write (Writer, Tarlib.Test_Fixtures.To_Bytes ("x"), Result);
      Assert
        (Result.Code = Tarlib.Errors.Invalid_Entry_Kind,
         "directory data rejected");
      Tarlib.Writers.End_Entry (Writer, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "directory end succeeds");
   end Test_Directory_Write_Rejected;

   procedure Test_GNU_Data_Entry_Kinds
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
      Writer    : Tarlib.Writers.Writer;
      Reader    : Tarlib.Readers.Reader;
      Info      : Tarlib.Readers.Entry_Info;
      Result    : Tarlib.Errors.Status;
      Has_Entry : Boolean;
      Multi_Data : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes ("part");
      Dump_Data : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes ("dump");
      Buffer    : Ada.Streams.Stream_Element_Array (1 .. 4);
      Last      : Ada.Streams.Stream_Element_Offset;
   begin
      Tarlib.Writers.Initialize (Writer, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "initialize");
      Tarlib.Writers.Begin_Entry
        (Writer, "continued.bin", Tarlib.Entries.Multi_Volume, 4,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Multi_Volume),
         Result);
      Assert (Result.Code = Tarlib.Errors.Success, "multi-volume begins");
      Tarlib.Writers.Write (Writer, Multi_Data, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "multi-volume data");
      Tarlib.Writers.End_Entry (Writer, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "multi-volume end");
      Tarlib.Writers.Begin_Entry
        (Writer, "directory", Tarlib.Entries.Incremental_Dump, 4,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Incremental_Dump),
         Result);
      Assert (Result.Code = Tarlib.Errors.Success, "incremental begins");
      Tarlib.Writers.Write (Writer, Dump_Data, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "incremental data");
      Tarlib.Writers.End_Entry (Writer, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "incremental end");
      Tarlib.Writers.Begin_Entry
        (Writer, "TARLIB_VOLUME", Tarlib.Entries.Volume_Label, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Volume_Label),
         Result);
      Assert (Result.Code = Tarlib.Errors.Success, "volume label begins");
      Tarlib.Writers.End_Entry (Writer, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "volume label end");
      Tarlib.Writers.Finish (Writer, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "finish");
      Assert
        (Tarlib.Test_Outputs.Element (Sink, 157) = Character'Pos ('M'),
         "multi-volume typeflag");
      Assert
        (Tarlib.Test_Outputs.Element (Sink, 1024 + 157) = Character'Pos ('D'),
         "incremental typeflag");
      Assert
        (Tarlib.Test_Outputs.Element (Sink, 2048 + 157) = Character'Pos ('V'),
         "volume label typeflag");

      Tarlib.Test_Outputs.Rewind (Sink);
      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");
      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert
        (Result.Code = Tarlib.Errors.Success and then Has_Entry,
         "multi-volume entry");
      Assert
        (Tarlib.Readers.Kind (Info) = Tarlib.Entries.Multi_Volume,
         "multi-volume kind");
      Tarlib.Readers.Read (Reader, Buffer, Last, Result);
      Assert
        (Result.Code = Tarlib.Errors.Success
         and then Last = 4
         and then Buffer = Multi_Data,
         "multi-volume payload");
      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert
        (Result.Code = Tarlib.Errors.Success and then Has_Entry,
         "incremental entry");
      Assert
        (Tarlib.Readers.Kind (Info) = Tarlib.Entries.Incremental_Dump,
         "incremental kind");
      Tarlib.Readers.Read (Reader, Buffer, Last, Result);
      Assert
        (Result.Code = Tarlib.Errors.Success
         and then Last = 4
         and then Buffer = Dump_Data,
         "incremental payload");
      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert
        (Result.Code = Tarlib.Errors.Success and then Has_Entry,
         "volume label entry");
      Assert
        (Tarlib.Readers.Kind (Info) = Tarlib.Entries.Volume_Label,
         "volume label kind");
   end Test_GNU_Data_Entry_Kinds;

   procedure Test_Sparse_File_Write
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      procedure Check (Format : Tarlib.Writers.Sparse_Format; Name : String) is
         Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
         Writer    : Tarlib.Writers.Writer;
         Reader    : Tarlib.Readers.Reader;
         Info      : Tarlib.Readers.Entry_Info;
         Result    : Tarlib.Errors.Status;
         Has_Entry : Boolean;
         Extents   : constant Tarlib.Entries.Sparse_Extent_Array :=
           [(Offset => 2, Length => 3), (Offset => 8, Length => 2),
            (Offset => 12, Length => 1), (Offset => 14, Length => 1),
            (Offset => 16, Length => 1)];
         Payload   : constant Ada.Streams.Stream_Element_Array :=
           Tarlib.Test_Fixtures.To_Bytes ("abcdeXYZ");
         Buffer    : Ada.Streams.Stream_Element_Array (1 .. 17);
         Last      : Ada.Streams.Stream_Element_Offset;
      begin
         Tarlib.Writers.Initialize (Writer, Sink, Result);
         Assert (Result.Code = Tarlib.Errors.Success, Name & " initialize");
         Tarlib.Writers.Begin_Sparse_File
           (Writer, "sparse.bin", 17, Extents, Format,
            Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File),
            Result);
         Assert (Result.Code = Tarlib.Errors.Success, Name & " begin sparse");
         Tarlib.Writers.Write (Writer, Payload, Result);
         Assert (Result.Code = Tarlib.Errors.Success, Name & " payload");
         Tarlib.Writers.End_Entry (Writer, Result);
         Assert (Result.Code = Tarlib.Errors.Success, Name & " end sparse");
         Tarlib.Writers.Finish (Writer, Result);
         Assert (Result.Code = Tarlib.Errors.Success, Name & " finish");

         Tarlib.Test_Outputs.Rewind (Sink);
         Tarlib.Readers.Initialize (Reader, Sink, Result);
         Assert (Result.Code = Tarlib.Errors.Success, Name & " reader");
         Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
         Assert
           (Result.Code = Tarlib.Errors.Success and then Has_Entry,
            Name & " entry");
         Assert (Tarlib.Readers.Size (Info) = 17, Name & " logical size");
         Tarlib.Readers.Read (Reader, Buffer, Last, Result);
         Assert
           (Result.Code = Tarlib.Errors.Success and then Last = 17,
            Name & " read sparse");
         Assert
           (Buffer =
              [0, 0, Character'Pos ('a'), Character'Pos ('b'),
               Character'Pos ('c'), 0, 0, 0, Character'Pos ('d'),
               Character'Pos ('e'), 0, 0, Character'Pos ('X'), 0,
               Character'Pos ('Y'), 0, Character'Pos ('Z')],
            Name & " holes reconstructed");
      end Check;
   begin
      Check (Tarlib.Writers.GNU_PAX_Sparse, "GNU PAX sparse");
      Check (Tarlib.Writers.Star_PAX_Sparse, "star PAX sparse");
      Check (Tarlib.Writers.Libarchive_PAX_Sparse, "libarchive PAX sparse");
      Check (Tarlib.Writers.Old_GNU_Sparse, "old GNU sparse");
   end Test_Sparse_File_Write;

   procedure Test_Link_Entries (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Sink   : aliased Tarlib.Test_Outputs.Memory_Sink;
      Writer : Tarlib.Writers.Writer;
      Result : Tarlib.Errors.Status;
      Short_NUL_Target : constant String := "bad" & Character'Val (0);
      NUL_Target : constant String := [1 .. 101 => 'a'] & Character'Val (0);
      Long_Path  : constant String := "links/" & [1 .. 120 => 'a'];
      Long_Absolute_Target : constant String := "/" & [1 .. 120 => 'c'];
      Long_Parent_Target : constant String := "../" & [1 .. 120 => 'b'];
   begin
      Tarlib.Writers.Initialize (Writer, Sink, Result);
      Tarlib.Writers.Add_Symbolic_Link
        (Writer, "latest", "releases/current", Result);
      Assert (Result.Code = Tarlib.Errors.Success, "symbolic link succeeds");
      Assert (Tarlib.Writers.State (Writer) = Tarlib.Writers.Ready, "ready");
      Assert (Tarlib.Test_Outputs.Length (Sink) = 512, "one link header");

      Tarlib.Writers.Add_Link
        (Writer, "bad", Tarlib.Entries.Regular_File, "target",
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File),
         Result);
      Assert
        (Result.Code = Tarlib.Errors.Invalid_Entry_Kind,
         "regular file rejected as link");

      Tarlib.Writers.Add_Hard_Link (Writer, "empty", "", Result);
      Assert
        (Result.Code = Tarlib.Errors.Invalid_Metadata,
         "empty hard link target rejected");
      Assert (Tarlib.Test_Outputs.Length (Sink) = 512, "no empty hard link header");

      Tarlib.Writers.Add_Hard_Link (Writer, "absolute", "/target", Result);
      Assert
        (Result.Code = Tarlib.Errors.Invalid_Path,
         "absolute hard link target rejected");
      Assert
        (Tarlib.Test_Outputs.Length (Sink) = 512,
         "no absolute hard link header");

      Tarlib.Writers.Add_Hard_Link (Writer, "parent", "../target", Result);
      Assert
        (Result.Code = Tarlib.Errors.Invalid_Path,
         "parent hard link target rejected");
      Assert
        (Tarlib.Test_Outputs.Length (Sink) = 512,
         "no parent hard link header");

      Tarlib.Writers.Add_Hard_Link
        (Writer, "long-absolute", Long_Absolute_Target, Result);
      Assert
        (Result.Code = Tarlib.Errors.Invalid_Path,
         "long absolute hard link target rejected before PAX");
      Assert
        (Tarlib.Test_Outputs.Length (Sink) = 512,
         "no long absolute hard link PAX header");

      Tarlib.Writers.Add_Hard_Link
        (Writer, "long-parent", Long_Parent_Target, Result);
      Assert
        (Result.Code = Tarlib.Errors.Invalid_Path,
         "long parent hard link target rejected before PAX");
      Assert
        (Tarlib.Test_Outputs.Length (Sink) = 512,
         "no long parent hard link PAX header");

      Tarlib.Writers.Add_Hard_Link
        (Writer, "nul-hard", Short_NUL_Target, Result);
      Assert
        (Result.Code = Tarlib.Errors.Invalid_Metadata,
         "NUL hard link target rejected");
      Assert
        (Tarlib.Test_Outputs.Length (Sink) = 512,
         "no NUL hard link header");

      Tarlib.Writers.Add_Hard_Link
        (Writer, "long-nul-hard", NUL_Target, Result);
      Assert
        (Result.Code = Tarlib.Errors.Invalid_Metadata,
         "long NUL hard link target rejected before PAX");
      Assert
        (Tarlib.Test_Outputs.Length (Sink) = 512,
         "no long NUL hard link PAX header");

      Tarlib.Writers.Add_Symbolic_Link (Writer, "abs-symlink", "/target", Result);
      Assert
        (Result.Code = Tarlib.Errors.Success,
         "absolute symbolic link target accepted");
      Assert
        (Tarlib.Test_Outputs.Length (Sink) = 1024,
         "absolute symbolic link header written");

      Tarlib.Writers.Add_Symbolic_Link
        (Writer, "nul-symlink", NUL_Target, Result);
      Assert
        (Result.Code = Tarlib.Errors.Invalid_Metadata,
         "NUL symbolic link target rejected");
      Assert
        (Tarlib.Test_Outputs.Length (Sink) = 1024,
         "no NUL symbolic link header");

      Tarlib.Writers.Add_Symbolic_Link (Writer, Long_Path, "", Result);
      Assert
        (Result.Code = Tarlib.Errors.Invalid_Metadata,
         "empty symbolic link target rejected");
      Assert
        (Tarlib.Test_Outputs.Length (Sink) = 1024,
         "no empty symlink PAX header");
   end Test_Link_Entries;

   procedure Test_Link_Metadata_PAX
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Sink     : aliased Tarlib.Test_Outputs.Memory_Sink;
      Writer   : Tarlib.Writers.Writer;
      Result   : Tarlib.Errors.Status;
      Metadata : Tarlib.Entries.Metadata :=
        Tarlib.Entries.Default_Metadata (Tarlib.Entries.Symbolic_Link);
   begin
      Metadata.MTime :=
        Tarlib.Entries.Timestamp (Tarlib.USTAR_Timestamp_Max) + 1;

      Tarlib.Writers.Initialize (Writer, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "initialize");
      Tarlib.Writers.Add_Link
        (Writer, "latest", Tarlib.Entries.Symbolic_Link, "target", Metadata,
         Result);
      Assert (Result.Code = Tarlib.Errors.Success, "link PAX metadata");
      Assert
        (Tarlib.Test_Outputs.Length (Sink) = 3 * 512,
         "PAX header, data block, and link header");
      Assert
        (Tarlib.Test_Outputs.Element (Sink, 157) = Character'Pos ('x'),
         "PAX typeflag");
      Assert
        (Tarlib.Test_Outputs.Element (Sink, 513 + 3) = Character'Pos ('m'),
         "PAX mtime keyword");
      Assert
        (Tarlib.Test_Outputs.Element (Sink, 1024 + 157) = Character'Pos ('2'),
         "symbolic link header");
      Assert
        (Tarlib.Test_Outputs.Element (Sink, 1024 + 137) = Character'Pos ('0'),
         "USTAR mtime placeholder");
   end Test_Link_Metadata_PAX;

   procedure Test_Long_Link_Target_PAX
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Symlink_Sink : aliased Tarlib.Test_Outputs.Memory_Sink;
      Hard_Sink    : aliased Tarlib.Test_Outputs.Memory_Sink;
      Symlink_Writer : Tarlib.Writers.Writer;
      Hard_Writer    : Tarlib.Writers.Writer;
      Result      : Tarlib.Errors.Status;
      Target      : constant String := [1 .. 101 => 't'];
      Hard_Target : constant String := "targets/" & [1 .. 101 => 'h'];
   begin
      Tarlib.Writers.Initialize (Symlink_Writer, Symlink_Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "initialize");
      Tarlib.Writers.Add_Symbolic_Link
        (Symlink_Writer, "latest", Target, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "long link target");
      Assert
        (Tarlib.Test_Outputs.Length (Symlink_Sink) = 3 * 512,
         "PAX header, data block, and link header");
      Assert
        (Tarlib.Test_Outputs.Element (Symlink_Sink, 157) = Character'Pos ('x'),
         "PAX typeflag");
      Assert
        (Tarlib.Test_Outputs.Element (Symlink_Sink, 513 + 4) =
         Character'Pos ('l'),
         "PAX linkpath keyword");
      Assert
        (Tarlib.Test_Outputs.Element (Symlink_Sink, 1024 + 157) =
         Character'Pos ('2'),
         "symbolic link header");

      Tarlib.Writers.Initialize (Hard_Writer, Hard_Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "hard initialize");
      Tarlib.Writers.Add_Hard_Link
        (Hard_Writer, "alias", Hard_Target, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "long hard link target");
      Assert
        (Tarlib.Test_Outputs.Length (Hard_Sink) = 3 * 512,
         "hard link PAX header, data block, and link header");
      Assert
        (Tarlib.Test_Outputs.Element (Hard_Sink, 157) = Character'Pos ('x'),
         "hard link PAX typeflag");
      Assert
        (Tarlib.Test_Outputs.Element (Hard_Sink, 513 + 4) =
         Character'Pos ('l'),
         "hard link PAX linkpath keyword");
      Assert
        (Tarlib.Test_Outputs.Element (Hard_Sink, 1024 + 157) =
         Character'Pos ('1'),
         "hard link header");
   end Test_Long_Link_Target_PAX;

   procedure Test_PAX_Oversized_File
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Sink   : aliased Tarlib.Test_Outputs.Memory_Sink;
      Writer : Tarlib.Writers.Writer;
      Result : Tarlib.Errors.Status;
      Size   : constant Tarlib.Byte_Count := Tarlib.USTAR_Size_Max + 1;
   begin
      Tarlib.Writers.Initialize (Writer, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "initialize");
      Tarlib.Writers.Begin_File (Writer, "huge.bin", Size, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "oversized file begins");
      Assert
        (Tarlib.Writers.State (Writer) = Tarlib.Writers.Writing_Entry,
         "writer is active");
      Assert
        (Tarlib.Test_Outputs.Length (Sink) = 3 * 512,
         "PAX header, PAX data block, and file header");
      Assert
        (Tarlib.Test_Outputs.Element (Sink, 157) = Character'Pos ('x'),
         "PAX typeflag");
      Assert
        (Tarlib.Test_Outputs.Element (Sink, 513 + 3) = Character'Pos ('s'),
         "PAX size keyword");
      Assert
        (Tarlib.Test_Outputs.Element (Sink, 512 + 512 + 157) =
         Character'Pos ('0'),
         "regular file placeholder header");
   end Test_PAX_Oversized_File;

   procedure Test_PAX_Oversized_MTime
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Sink     : aliased Tarlib.Test_Outputs.Memory_Sink;
      Writer   : Tarlib.Writers.Writer;
      Result   : Tarlib.Errors.Status;
      Metadata : Tarlib.Entries.Metadata :=
        Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File);
   begin
      Metadata.MTime :=
        Tarlib.Entries.Timestamp (Tarlib.USTAR_Timestamp_Max) + 1;

      Tarlib.Writers.Initialize (Writer, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "initialize");
      Tarlib.Writers.Begin_Entry
        (Writer, "future.txt", Tarlib.Entries.Regular_File, 0, Metadata,
         Result);
      Assert (Result.Code = Tarlib.Errors.Success, "future mtime begins");
      Assert
        (Tarlib.Test_Outputs.Length (Sink) = 3 * 512,
         "PAX header, PAX data block, and file header");
      Assert
        (Tarlib.Test_Outputs.Element (Sink, 157) = Character'Pos ('x'),
         "PAX typeflag");
      Assert
        (Tarlib.Test_Outputs.Element (Sink, 513 + 3) = Character'Pos ('m'),
         "PAX mtime keyword");
      Assert
        (Tarlib.Test_Outputs.Element (Sink, 512 + 512 + 137) =
         Character'Pos ('0'),
         "USTAR mtime placeholder");
   end Test_PAX_Oversized_MTime;

   procedure Test_PAX_Negative_MTime
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
   begin
      Metadata.MTime := -1;

      Tarlib.Writers.Initialize (Writer, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "initialize");
      Tarlib.Writers.Begin_Entry
        (Writer, "past.txt", Tarlib.Entries.Regular_File, 0, Metadata,
         Result);
      Assert (Result.Code = Tarlib.Errors.Success, "past mtime begins");
      Tarlib.Writers.End_Entry (Writer, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "end entry");
      Tarlib.Writers.Finish (Writer, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "finish");
      Assert
        (Tarlib.Test_Outputs.Element (Sink, 157) = Character'Pos ('x'),
         "PAX typeflag");
      Assert
        (Tarlib.Test_Outputs.Element (Sink, 513 + 3) = Character'Pos ('m'),
         "PAX mtime keyword");
      Assert
        (Tarlib.Test_Outputs.Element (Sink, 1024 + 137) = Character'Pos ('0'),
         "USTAR mtime placeholder");

      Tarlib.Test_Outputs.Rewind (Sink);
      Tarlib.Readers.Initialize (Reader, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "reader initialize");
      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      Assert
        (Result.Code = Tarlib.Errors.Success and then Has_Entry,
         "read written entry");
      Assert
        (Tarlib.Readers.Metadata (Info).MTime = -1,
         "negative mtime roundtrip");
   end Test_PAX_Negative_MTime;

   procedure Test_PAX_Oversized_Owner
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Sink     : aliased Tarlib.Test_Outputs.Memory_Sink;
      Writer   : Tarlib.Writers.Writer;
      Result   : Tarlib.Errors.Status;
      Metadata : Tarlib.Entries.Metadata :=
        Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File);
   begin
      Metadata.UID := Tarlib.Entries.Owner_Id (Tarlib.USTAR_Owner_Max + 1);
      Metadata.GID := Tarlib.Entries.Owner_Id (Tarlib.USTAR_Owner_Max + 2);

      Tarlib.Writers.Initialize (Writer, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "initialize");
      Tarlib.Writers.Begin_Entry
        (Writer, "owner.txt", Tarlib.Entries.Regular_File, 0, Metadata,
         Result);
      Assert (Result.Code = Tarlib.Errors.Success, "owner begins");
      Assert
        (Tarlib.Test_Outputs.Length (Sink) = 3 * 512,
         "combined PAX record and file header");
      Assert
        (Tarlib.Test_Outputs.Element (Sink, 157) = Character'Pos ('x'),
         "UID PAX typeflag");
      Assert
        (Tarlib.Test_Outputs.Element (Sink, 513 + 3) = Character'Pos ('u'),
         "UID keyword");
      Assert
        (Tarlib.Test_Outputs.Element (Sink, 513 + 18) = Character'Pos ('g'),
         "GID keyword");
      Assert
        (Tarlib.Test_Outputs.Element (Sink, 1024 + 109) =
         Character'Pos ('0'),
         "USTAR UID placeholder");
      Assert
        (Tarlib.Test_Outputs.Element (Sink, 1024 + 117) =
         Character'Pos ('0'),
         "USTAR GID placeholder");
   end Test_PAX_Oversized_Owner;

   procedure Test_Combined_PAX_Overrides
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Sink     : aliased Tarlib.Test_Outputs.Memory_Sink;
      Writer   : Tarlib.Writers.Writer;
      Result   : Tarlib.Errors.Status;
      Metadata : Tarlib.Entries.Metadata :=
        Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File);
      Long_Path : constant String :=
        "combined/" & [1 .. 120 => 'a'] & "/" & [1 .. 120 => 'b'];
   begin
      Metadata.MTime :=
        Tarlib.Entries.Timestamp (Tarlib.USTAR_Timestamp_Max) + 1;
      Metadata.ATime := 123;
      Metadata.CTime := 456;
      Metadata.UID := Tarlib.Entries.Owner_Id (Tarlib.USTAR_Owner_Max + 1);

      Tarlib.Writers.Initialize (Writer, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "initialize");
      Tarlib.Writers.Begin_Entry
        (Writer, Long_Path, Tarlib.Entries.Regular_File, 0, Metadata,
         Result);
      Assert (Result.Code = Tarlib.Errors.Success, "combined PAX begins");
      Assert
        (Tarlib.Test_Outputs.Length (Sink) = 3 * 512,
         "one PAX header and file header");
      Assert
        (Tarlib.Test_Outputs.Element (Sink, 157) = Character'Pos ('x'),
         "single PAX typeflag");
      Assert
        (Tarlib.Test_Outputs.Element (Sink, 513 + 4) = Character'Pos ('p'),
         "path keyword first");
      Assert
        (Tarlib.Test_Outputs.Element (Sink, 1024 + 157) = Character'Pos ('0'),
         "file header follows combined PAX block");
   end Test_Combined_PAX_Overrides;

   procedure Test_PAX_Record_Too_Large
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Sink      : aliased Tarlib.Test_Outputs.Memory_Sink;
      Writer    : Tarlib.Writers.Writer;
      Result    : Tarlib.Errors.Status;
      Huge_Path : constant String := "huge/" & [1 .. Tarlib.Max_PAX_Data => 'a'];
   begin
      Tarlib.Writers.Initialize (Writer, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "initialize");
      Tarlib.Writers.Begin_File (Writer, Huge_Path, 0, Result);
      Assert
        (Result.Code = Tarlib.Errors.Invalid_Metadata,
         "oversized PAX path rejected before write");
      Assert
        (Tarlib.Writers.State (Writer) = Tarlib.Writers.Ready,
         "writer remains ready");
      Assert (Tarlib.Test_Outputs.Length (Sink) = 0, "no partial output");
   end Test_PAX_Record_Too_Large;

   procedure Test_PAX_Owner_Names
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Sink     : aliased Tarlib.Test_Outputs.Memory_Sink;
      Writer   : Tarlib.Writers.Writer;
      Result   : Tarlib.Errors.Status;
      Metadata : Tarlib.Entries.Metadata :=
        Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File);
      Long_User : constant String := [1 .. 40 => 'u'];
      Long_Group : constant String := [1 .. 40 => 'g'];
   begin
      Tarlib.Entries.Set_Text (Metadata.User_Name, Long_User, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "user set");
      Tarlib.Entries.Set_Text (Metadata.Group_Name, Long_Group, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "group set");

      Tarlib.Writers.Initialize (Writer, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "initialize");
      Tarlib.Writers.Begin_Entry
        (Writer, "names.txt", Tarlib.Entries.Regular_File, 0, Metadata,
         Result);
      Assert (Result.Code = Tarlib.Errors.Success, "names begins");
      Assert
        (Tarlib.Test_Outputs.Length (Sink) = 3 * 512,
         "PAX names and file header");
      Assert
        (Tarlib.Test_Outputs.Element (Sink, 157) = Character'Pos ('x'),
         "PAX typeflag");
      Assert
        (Tarlib.Test_Outputs.Element (Sink, 516) = Character'Pos ('u'),
         "uname keyword");
      Assert
        (Tarlib.Test_Outputs.Element (Sink, 566) = Character'Pos ('g'),
         "gname keyword");
      Assert
        (Tarlib.Test_Outputs.Element (Sink, 1024 + 266) = 0,
         "USTAR user placeholder");
      Assert
        (Tarlib.Test_Outputs.Element (Sink, 1024 + 298) = 0,
         "USTAR group placeholder");
   end Test_PAX_Owner_Names;

   procedure Test_Extended_Record_Injection
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Sink   : aliased Tarlib.Test_Outputs.Memory_Sink;
      Writer : Tarlib.Writers.Writer;
      Result : Tarlib.Errors.Status;
   begin
      Tarlib.Writers.Initialize (Writer, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "initialize");
      Tarlib.Writers.Add_Extended_Record
        (Writer, "LIBARCHIVE.note", "hello", Result);
      Assert (Result.Code = Tarlib.Errors.Success, "extension emitted");
      Assert
        (Tarlib.Test_Outputs.Length (Sink) = 2 * 512,
         "PAX header and data block");
      Assert
        (Tarlib.Test_Outputs.Element (Sink, 157) = Character'Pos ('x'),
         "PAX typeflag");
      Tarlib.Writers.Begin_File (Writer, "file.txt", 0, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "next entry begins");

      Tarlib.Writers.Add_Extended_Record (Writer, "", "bad", Result);
      Assert
        (Result.Code = Tarlib.Errors.Invalid_State,
         "extension while active rejected by state");
      Tarlib.Writers.End_Entry (Writer, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "end file");
      Tarlib.Writers.Add_Extended_Record (Writer, "bad=key", "bad", Result);
      Assert
        (Result.Code = Tarlib.Errors.Invalid_Metadata,
         "invalid key rejected");
   end Test_Extended_Record_Injection;

   procedure Test_Special_Entries (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Sink   : aliased Tarlib.Test_Outputs.Memory_Sink;
      Writer : Tarlib.Writers.Writer;
      Result : Tarlib.Errors.Status;
      Device : constant Tarlib.Entries.Device_Numbers :=
        (Major => 1, Minor => 3);
      Long_FIFO : constant String := "fifo/" & [1 .. 120 => 'f'];
   begin
      Tarlib.Writers.Initialize (Writer, Sink, Result);
      Tarlib.Writers.Add_Character_Device (Writer, "dev/null", Device, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "character device succeeds");
      Tarlib.Writers.Add_Block_Device (Writer, "dev/disk0", Device, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "block device succeeds");
      Tarlib.Writers.Add_FIFO (Writer, "run/pipe", Result);
      Assert (Result.Code = Tarlib.Errors.Success, "fifo succeeds");
      Assert
        (Tarlib.Test_Outputs.Length (Sink) = 3 * 512,
         "three special headers");

      Tarlib.Writers.Add_Special
        (Writer, "bad", Tarlib.Entries.Regular_File, Tarlib.Entries.No_Device,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File),
         Result);
      Assert
        (Result.Code = Tarlib.Errors.Invalid_Entry_Kind,
         "regular file rejected as special");

      Tarlib.Writers.Add_Special
        (Writer, "bad-fifo", Tarlib.Entries.FIFO, Device,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.FIFO),
         Result);
      Assert
        (Result.Code = Tarlib.Errors.Invalid_Metadata,
         "FIFO device numbers rejected");
      Assert
        (Tarlib.Test_Outputs.Length (Sink) = 3 * 512,
         "no invalid FIFO header");

      Tarlib.Writers.Add_Special
        (Writer, Long_FIFO, Tarlib.Entries.FIFO, Device,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.FIFO),
         Result);
      Assert
        (Result.Code = Tarlib.Errors.Invalid_Metadata,
         "long FIFO device numbers rejected");
      Assert
        (Tarlib.Test_Outputs.Length (Sink) = 3 * 512,
         "no invalid FIFO PAX header");
   end Test_Special_Entries;

   procedure Test_Special_Metadata_PAX
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Sink     : aliased Tarlib.Test_Outputs.Memory_Sink;
      Writer   : Tarlib.Writers.Writer;
      Result   : Tarlib.Errors.Status;
      Metadata : Tarlib.Entries.Metadata :=
        Tarlib.Entries.Default_Metadata (Tarlib.Entries.FIFO);
   begin
      Metadata.UID := Tarlib.Entries.Owner_Id (Tarlib.USTAR_Owner_Max + 1);

      Tarlib.Writers.Initialize (Writer, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "initialize");
      Tarlib.Writers.Add_Special
        (Writer, "run/pipe", Tarlib.Entries.FIFO, Tarlib.Entries.No_Device,
         Metadata, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "special PAX metadata");
      Assert
        (Tarlib.Test_Outputs.Length (Sink) = 3 * 512,
         "PAX header, data block, and FIFO header");
      Assert
        (Tarlib.Test_Outputs.Element (Sink, 157) = Character'Pos ('x'),
         "PAX typeflag");
      Assert
        (Tarlib.Test_Outputs.Element (Sink, 513 + 3) = Character'Pos ('u'),
         "PAX uid keyword");
      Assert
        (Tarlib.Test_Outputs.Element (Sink, 1024 + 157) = Character'Pos ('6'),
         "FIFO header");
      Assert
        (Tarlib.Test_Outputs.Element (Sink, 1024 + 109) = Character'Pos ('0'),
         "USTAR UID placeholder");
   end Test_Special_Metadata_PAX;

   procedure Test_Finish_And_Failure
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Sink   : aliased Tarlib.Test_Outputs.Memory_Sink;
      Writer : Tarlib.Writers.Writer;
      Result : Tarlib.Errors.Status;
      Failed_Sink   : aliased Tarlib.Test_Outputs.Memory_Sink;
      Failed_Writer : Tarlib.Writers.Writer;
      Data          : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes ("x");
   begin
      Tarlib.Writers.Initialize (Writer, Sink, Result);
      Tarlib.Writers.Finish (Writer, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "finish succeeds");
      Assert (Tarlib.Writers.State (Writer) = Tarlib.Writers.Finished, "finished state");
      Tarlib.Writers.Finish (Writer, Result);
      Assert (Result.Code = Tarlib.Errors.Already_Finished, "double finish rejected");
      Tarlib.Writers.Begin_File (Writer, "late", 0, Result);
      Assert (Result.Code = Tarlib.Errors.Already_Finished, "begin after finish rejected");

      Tarlib.Test_Outputs.Fail_After (Failed_Sink, 0);
      Tarlib.Writers.Initialize (Failed_Writer, Failed_Sink, Result);
      Tarlib.Writers.Begin_File (Failed_Writer, "a", 0, Result);
      Assert (Result.Code = Tarlib.Errors.Output_Failure, "header output failure reported");
      Assert
        (Tarlib.Writers.State (Failed_Writer) = Tarlib.Writers.Failed,
         "failed state is terminal");
      Tarlib.Writers.Begin_File (Failed_Writer, "again", 0, Result);
      Assert
        (Result.Code = Tarlib.Errors.Output_Failure,
         "begin after output failure rejected");
      Tarlib.Writers.Add_Directory (Failed_Writer, "dir/", Result);
      Assert
        (Result.Code = Tarlib.Errors.Output_Failure,
         "directory after output failure rejected");
      Tarlib.Writers.Add_Symbolic_Link
        (Failed_Writer, "link", "target", Result);
      Assert
        (Result.Code = Tarlib.Errors.Output_Failure,
         "link after output failure rejected");
      Tarlib.Writers.Add_FIFO (Failed_Writer, "pipe", Result);
      Assert
        (Result.Code = Tarlib.Errors.Output_Failure,
         "special after output failure rejected");
      Tarlib.Writers.Write (Failed_Writer, Data, Result);
      Assert
        (Result.Code = Tarlib.Errors.Output_Failure,
         "write after output failure rejected");
      Tarlib.Writers.End_Entry (Failed_Writer, Result);
      Assert
        (Result.Code = Tarlib.Errors.Output_Failure,
         "end after output failure rejected");
      Tarlib.Writers.Finish (Failed_Writer, Result);
      Assert (Result.Code = Tarlib.Errors.Output_Failure, "failed writer stays failed");
   end Test_Finish_And_Failure;

   overriding procedure Register_Tests (T : in out Test_Case) is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine
        (T, Test_Initialization'Access, "initialization");
      Registration.Register_Routine
        (T, Test_Invalid_Sequences'Access, "invalid call sequences");
      Registration.Register_Routine
        (T, Test_Exact_Completion'Access, "exact data completion");
      Registration.Register_Routine
        (T, Test_Directory_Write_Rejected'Access, "directory write rejection");
      Registration.Register_Routine
        (T, Test_GNU_Data_Entry_Kinds'Access, "GNU data entry kinds");
      Registration.Register_Routine
        (T, Test_Sparse_File_Write'Access, "sparse file write");
      Registration.Register_Routine
        (T, Test_Link_Entries'Access, "link entries");
      Registration.Register_Routine
        (T, Test_Link_Metadata_PAX'Access, "link PAX metadata");
      Registration.Register_Routine
        (T, Test_Long_Link_Target_PAX'Access, "long link target PAX");
      Registration.Register_Routine
        (T, Test_PAX_Oversized_File'Access, "PAX oversized file");
      Registration.Register_Routine
        (T, Test_PAX_Oversized_MTime'Access, "PAX oversized mtime");
      Registration.Register_Routine
        (T, Test_PAX_Negative_MTime'Access, "PAX negative mtime");
      Registration.Register_Routine
        (T, Test_PAX_Oversized_Owner'Access, "PAX oversized owner");
      Registration.Register_Routine
        (T, Test_Combined_PAX_Overrides'Access, "combined PAX overrides");
      Registration.Register_Routine
        (T, Test_PAX_Record_Too_Large'Access, "oversized PAX record");
      Registration.Register_Routine
        (T, Test_PAX_Owner_Names'Access, "PAX owner names");
      Registration.Register_Routine
        (T, Test_Extended_Record_Injection'Access,
         "extended record injection");
      Registration.Register_Routine
        (T, Test_Special_Entries'Access, "special entries");
      Registration.Register_Routine
        (T, Test_Special_Metadata_PAX'Access, "special PAX metadata");
      Registration.Register_Routine
        (T, Test_Finish_And_Failure'Access, "finish and output failure");
   end Register_Tests;
end Tarlib.Writer_Tests;
