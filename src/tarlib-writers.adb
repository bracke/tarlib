with Interfaces;
with Tarlib.Internal.Checksums;
with Tarlib.Internal.Constants;
with Tarlib.Internal.Fields;
with Tarlib.Internal.Headers;
with Tarlib.Internal.Padding;
with Tarlib.Internal.Paths;

package body Tarlib.Writers is
   use type Ada.Streams.Stream_Element_Offset;
   use type Interfaces.Integer_64;
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;
   use type Tarlib.Entries.Entry_Kind;
   use type Tarlib.Errors.Status_Code;

   procedure Mark_Output_Failure
     (Archive : in out Writer;
      Result  : Tarlib.Errors.Status) is
   begin
      if Result.Code /= Tarlib.Errors.Success then
         Archive.Current_State := Failed;
      end if;
   end Mark_Output_Failure;

   function Contains_NUL (Text : String) return Boolean is
   begin
      for Character_Value of Text loop
         if Character_Value = Character'Val (0) then
            return True;
         end if;
      end loop;

      return False;
   end Contains_NUL;

   procedure Write_Block
     (Archive : in out Writer;
      Block   : Tarlib.Internal.Constants.Header_Block;
      Result  : out Tarlib.Errors.Status) is
   begin
      Archive.Destination.Write
        (Ada.Streams.Stream_Element_Array (Block), Result);
      Mark_Output_Failure (Archive, Result);
   end Write_Block;

   function Decimal_Length (Value : Natural) return Natural is
      Work   : Natural := Value;
      Result : Natural := 1;
   begin
      while Work >= 10 loop
         Work := Work / 10;
         Result := Result + 1;
      end loop;

      return Result;
   end Decimal_Length;

   function Decimal_Length (Value : Interfaces.Unsigned_64) return Natural is
      Work   : Interfaces.Unsigned_64 := Value;
      Result : Natural := 1;
   begin
      while Work >= 10 loop
         Work := Work / 10;
         Result := Result + 1;
      end loop;

      return Result;
   end Decimal_Length;

   procedure Put_Decimal
     (Target : in out String;
      Cursor : in out Natural;
      Value  : Natural)
   is
      Length : constant Natural := Decimal_Length (Value);
      Work   : Natural := Value;
   begin
      for Offset in reverse 0 .. Length - 1 loop
         Target (Cursor + Offset) :=
           Character'Val (Character'Pos ('0') + Work mod 10);
         Work := Work / 10;
      end loop;
      Cursor := Cursor + Length;
   end Put_Decimal;

   function Decimal_Text (Value : Interfaces.Unsigned_64) return String is
      Result : String (1 .. Decimal_Length (Value));
      Work   : Interfaces.Unsigned_64 := Value;
   begin
      for Index in reverse Result'Range loop
         Result (Index) :=
           Character'Val
             (Character'Pos ('0') + Natural (Work mod 10));
         Work := Work / 10;
      end loop;

      return Result;
   end Decimal_Text;

   function Decimal_Text (Value : Interfaces.Integer_64) return String is
   begin
      if Value < 0 then
         return
           "-"
           & Decimal_Text
               (Interfaces.Unsigned_64
                  (-(Value + Interfaces.Integer_64'(1)))
                + Interfaces.Unsigned_64'(1));
      else
         return Decimal_Text (Interfaces.Unsigned_64 (Value));
      end if;
   end Decimal_Text;

   function Sparse_Map_Text
     (Extents : Tarlib.Entries.Sparse_Extent_Array) return String
   is
      Length : Natural := 0;
   begin
      for Extent of Extents loop
         if Length > 0 then
            Length := Length + 1;
         end if;
         Length :=
           Length
           + Decimal_Length (Interfaces.Unsigned_64 (Extent.Offset))
           + 1
           + Decimal_Length (Interfaces.Unsigned_64 (Extent.Length));
      end loop;

      declare
         Result : String (1 .. Length);
         Cursor : Natural := Result'First;
      begin
         for Extent of Extents loop
            if Cursor > Result'First then
               Result (Cursor) := ',';
               Cursor := Cursor + 1;
            end if;
            declare
               Offset_Text : constant String :=
                 Decimal_Text (Interfaces.Unsigned_64 (Extent.Offset));
               Length_Text : constant String :=
                 Decimal_Text (Interfaces.Unsigned_64 (Extent.Length));
            begin
               Result (Cursor .. Cursor + Offset_Text'Length - 1) :=
                 Offset_Text;
               Cursor := Cursor + Offset_Text'Length;
               Result (Cursor) := ',';
               Cursor := Cursor + 1;
               Result (Cursor .. Cursor + Length_Text'Length - 1) :=
                 Length_Text;
               Cursor := Cursor + Length_Text'Length;
            end;
         end loop;

         return Result;
      end;
   end Sparse_Map_Text;

   procedure Validate_Sparse_Extents
     (Logical_Size  : Tarlib.Byte_Count;
      Extents       : Tarlib.Entries.Sparse_Extent_Array;
      Physical_Size : out Tarlib.Byte_Count;
      Result        : out Tarlib.Errors.Status)
   is
      Last_End : Tarlib.Byte_Count := 0;
   begin
      Physical_Size := 0;
      if Extents'Length = 0 then
         Result := (Code => Tarlib.Errors.Invalid_Metadata);
         return;
      end if;

      for Extent of Extents loop
         if Extent.Length = 0
           or else Extent.Length > Tarlib.Byte_Count'Last - Extent.Offset
           or else Extent.Offset < Last_End
           or else Extent.Offset + Extent.Length > Logical_Size
           or else Extent.Length > Tarlib.Byte_Count'Last - Physical_Size
         then
            Result := (Code => Tarlib.Errors.Invalid_Metadata);
            return;
         end if;

         Last_End := Extent.Offset + Extent.Length;
         Physical_Size := Physical_Size + Extent.Length;
      end loop;

      Result := Tarlib.Errors.OK;
   end Validate_Sparse_Extents;

   procedure Put_Sparse_Extent
     (Block  : in out Tarlib.Internal.Constants.Header_Block;
      First  : Ada.Streams.Stream_Element_Offset;
      Extent : Tarlib.Entries.Sparse_Extent;
      Result : out Tarlib.Errors.Status)
   is
   begin
      Tarlib.Internal.Fields.Put_Octal
        (Block (First .. First + 11),
         Interfaces.Unsigned_64 (Extent.Offset),
         Tarlib.Internal.Fields.NUL_Terminated, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Tarlib.Internal.Fields.Put_Octal
        (Block (First + 12 .. First + 23),
         Interfaces.Unsigned_64 (Extent.Length),
         Tarlib.Internal.Fields.NUL_Terminated, Result);
   end Put_Sparse_Extent;

   function PAX_Record_Length
     (Keyword : String;
      Value   : String) return Natural
   is
      Payload_Length : constant Natural :=
        Keyword'Length + 1 + Value'Length + 1;
      Result         : Natural := Payload_Length + 2;
      Next_Result    : Natural;
   begin
      loop
         Next_Result := Payload_Length + Decimal_Length (Result) + 1;
         exit when Next_Result = Result;
         Result := Next_Result;
      end loop;

      return Result;
   end PAX_Record_Length;

   function PAX_Record
     (Keyword : String;
      Value   : String) return Ada.Streams.Stream_Element_Array
   is
      Length : constant Natural := PAX_Record_Length (Keyword, Value);
      Text   : String (1 .. Length);
      Cursor : Natural := Text'First;
      Result : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Length));
   begin
      Put_Decimal (Text, Cursor, Length);
      Text (Cursor) := ' ';
      Cursor := Cursor + 1;
      Text (Cursor .. Cursor + Keyword'Length - 1) := Keyword;
      Cursor := Cursor + Keyword'Length;
      Text (Cursor) := '=';
      Cursor := Cursor + 1;
      Text (Cursor .. Cursor + Value'Length - 1) := Value;
      Cursor := Cursor + Value'Length;
      Text (Cursor) := Character'Val (10);

      for Index in Result'Range loop
         Result (Index) :=
           Ada.Streams.Stream_Element
             (Character'Pos (Text (Natural (Index - Result'First) + 1)));
      end loop;

      return Result;
   end PAX_Record;

   procedure Write_Raw
     (Archive : in out Writer;
      Data    : Ada.Streams.Stream_Element_Array;
      Result  : out Tarlib.Errors.Status) is
   begin
      if Data'Length > 0 then
         Archive.Destination.Write (Data, Result);
         Mark_Output_Failure (Archive, Result);
      else
         Result := Tarlib.Errors.OK;
      end if;
   end Write_Raw;

   procedure Write_Padding
     (Archive : in out Writer;
      Size    : Tarlib.Byte_Count;
      Result  : out Tarlib.Errors.Status)
   is
      Padding : constant Natural :=
        Tarlib.Internal.Padding.Padding_Length (Size);
      Block   : constant Tarlib.Internal.Constants.Header_Block :=
        Tarlib.Internal.Constants.Zero_Block;
   begin
      if Padding > 0 then
         Write_Raw
           (Archive,
            Block (1 .. Ada.Streams.Stream_Element_Offset (Padding)),
            Result);
      else
         Result := Tarlib.Errors.OK;
      end if;
   end Write_Padding;

   procedure Write_PAX_Record_Header
     (Archive : in out Writer;
      Data    : Ada.Streams.Stream_Element_Array;
      Result  : out Tarlib.Errors.Status)
   is
      Header : Tarlib.Internal.Constants.Header_Block;
      Size   : constant Tarlib.Byte_Count := Tarlib.Byte_Count (Data'Length);
   begin
      Tarlib.Internal.Headers.Build
        ("PaxHeaders/tarlib-pax", Tarlib.Entries.PAX_Extended_Header, Size,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.PAX_Extended_Header),
         Header, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Write_Block (Archive, Header, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Write_Raw (Archive, Data, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Write_Padding (Archive, Size, Result);
   end Write_PAX_Record_Header;

   type PAX_Buffer is record
      Data : Ada.Streams.Stream_Element_Array (1 .. Tarlib.Max_PAX_Data) :=
        [others => 0];
      Last : Natural := 0;
   end record;

   procedure Append_PAX_Record
     (PAX     : in out PAX_Buffer;
      Keyword : String;
      Value   : String;
      Result  : out Tarlib.Errors.Status)
   is
      Length      : Natural;
      Target_Last : Natural;
   begin
      if Keyword'Length = 0 or else Contains_NUL (Keyword)
        or else Contains_NUL (Value)
      then
         Result := (Code => Tarlib.Errors.Invalid_Metadata);
         return;
      end if;

      for Character_Value of Keyword loop
         if Character_Value = '=' or else Character_Value = Character'Val (10)
         then
            Result := (Code => Tarlib.Errors.Invalid_Metadata);
            return;
         end if;
      end loop;

      for Character_Value of Value loop
         if Character_Value = Character'Val (10) then
            Result := (Code => Tarlib.Errors.Invalid_Metadata);
            return;
         end if;
      end loop;

      if Keyword'Length > Tarlib.Max_PAX_Data
        or else Value'Length > Tarlib.Max_PAX_Data
      then
         Result := (Code => Tarlib.Errors.Invalid_Metadata);
         return;
      end if;

      Length := PAX_Record_Length (Keyword, Value);
      if Length > Tarlib.Max_PAX_Data
        or else PAX.Last > Tarlib.Max_PAX_Data - Length
      then
         Result := (Code => Tarlib.Errors.Invalid_Metadata);
         return;
      end if;

      declare
         Record_Data : constant Ada.Streams.Stream_Element_Array :=
           PAX_Record (Keyword, Value);
      begin
         Target_Last := PAX.Last + Record_Data'Length;
         for Index in Record_Data'Range loop
            PAX.Last := PAX.Last + 1;
            PAX.Data (Ada.Streams.Stream_Element_Offset (PAX.Last)) :=
              Record_Data (Index);
         end loop;
         pragma Assert (PAX.Last = Target_Last);
      end;

      Result := Tarlib.Errors.OK;
   end Append_PAX_Record;

   procedure Append_PAX_Size
     (PAX    : in out PAX_Buffer;
      Size   : Tarlib.Byte_Count;
      Result : out Tarlib.Errors.Status) is
   begin
      Append_PAX_Record
        (PAX, "size", Decimal_Text (Interfaces.Unsigned_64 (Size)), Result);
   end Append_PAX_Size;

   procedure Append_PAX_MTime
     (PAX    : in out PAX_Buffer;
      MTime  : Tarlib.Entries.Timestamp;
      Result : out Tarlib.Errors.Status) is
   begin
      Append_PAX_Record
        (PAX, "mtime", Decimal_Text (MTime), Result);
   end Append_PAX_MTime;

   procedure Append_PAX_Time
     (PAX     : in out PAX_Buffer;
      Keyword : String;
      Time    : Tarlib.Entries.Timestamp;
      Result  : out Tarlib.Errors.Status) is
   begin
      Append_PAX_Record (PAX, Keyword, Decimal_Text (Time), Result);
   end Append_PAX_Time;

   procedure Append_PAX_UID
     (PAX    : in out PAX_Buffer;
      UID    : Tarlib.Entries.Owner_Id;
      Result : out Tarlib.Errors.Status) is
   begin
      Append_PAX_Record
        (PAX, "uid", Decimal_Text (Interfaces.Unsigned_64 (UID)), Result);
   end Append_PAX_UID;

   procedure Append_PAX_GID
     (PAX    : in out PAX_Buffer;
      GID    : Tarlib.Entries.Owner_Id;
      Result : out Tarlib.Errors.Status) is
   begin
      Append_PAX_Record
        (PAX, "gid", Decimal_Text (Interfaces.Unsigned_64 (GID)), Result);
   end Append_PAX_GID;

   procedure Write_PAX_Records
     (Archive : in out Writer;
      PAX     : PAX_Buffer;
      Result  : out Tarlib.Errors.Status) is
   begin
      if PAX.Last = 0 then
         Result := Tarlib.Errors.OK;
         return;
      end if;

      Write_PAX_Record_Header
        (Archive, PAX.Data (1 .. Ada.Streams.Stream_Element_Offset (PAX.Last)),
         Result);
   end Write_PAX_Records;

   procedure Append_PAX_Metadata
     (PAX      : in out PAX_Buffer;
      Metadata : Tarlib.Entries.Metadata;
      Header_Metadata : in out Tarlib.Entries.Metadata;
      Result   : out Tarlib.Errors.Status)
   is
      User_Name  : constant String := Tarlib.Entries.Text (Metadata.User_Name);
      Group_Name : constant String := Tarlib.Entries.Text (Metadata.Group_Name);
   begin
      if User_Name'Length > 32 then
         Append_PAX_Record (PAX, "uname", User_Name, Result);
         if Result.Code /= Tarlib.Errors.Success then
            return;
         end if;
         Header_Metadata.User_Name := (others => <>);
      end if;

      if Group_Name'Length > 32 then
         Append_PAX_Record (PAX, "gname", Group_Name, Result);
         if Result.Code /= Tarlib.Errors.Success then
            return;
         end if;
         Header_Metadata.Group_Name := (others => <>);
      end if;

      if Metadata.MTime < 0
        or else Interfaces.Unsigned_64 (Metadata.MTime)
                > Tarlib.USTAR_Timestamp_Max
      then
         Append_PAX_MTime (PAX, Metadata.MTime, Result);
         if Result.Code /= Tarlib.Errors.Success then
            return;
         end if;
         Header_Metadata.MTime := 0;
      end if;

      if Metadata.ATime /= Tarlib.Entries.Default_Timestamp then
         Append_PAX_Time (PAX, "atime", Metadata.ATime, Result);
         if Result.Code /= Tarlib.Errors.Success then
            return;
         end if;
         Header_Metadata.ATime := Tarlib.Entries.Default_Timestamp;
      end if;

      if Metadata.CTime /= Tarlib.Entries.Default_Timestamp then
         Append_PAX_Time (PAX, "ctime", Metadata.CTime, Result);
         if Result.Code /= Tarlib.Errors.Success then
            return;
         end if;
         Header_Metadata.CTime := Tarlib.Entries.Default_Timestamp;
      end if;

      if Interfaces.Unsigned_64 (Metadata.UID) > Tarlib.USTAR_Owner_Max then
         Append_PAX_UID (PAX, Metadata.UID, Result);
         if Result.Code /= Tarlib.Errors.Success then
            return;
         end if;
         Header_Metadata.UID := 0;
      end if;

      if Interfaces.Unsigned_64 (Metadata.GID) > Tarlib.USTAR_Owner_Max then
         Append_PAX_GID (PAX, Metadata.GID, Result);
         if Result.Code /= Tarlib.Errors.Success then
            return;
         end if;
         Header_Metadata.GID := 0;
      end if;

      Result := Tarlib.Errors.OK;
   end Append_PAX_Metadata;

   procedure Prepare_Header_Path
     (PAX         : in out PAX_Buffer;
      Path        : String;
      Header_Path : out String;
      Last        : out Natural;
      Result      : out Tarlib.Errors.Status)
   is
      Split : constant Tarlib.Internal.Paths.Path_Split :=
        Tarlib.Internal.Paths.Split (Path);
   begin
      if Split.Status.Code = Tarlib.Errors.Success then
         Header_Path (Header_Path'First .. Header_Path'First + Path'Length - 1) :=
           Path;
         Last := Header_Path'First + Path'Length - 1;
         Result := Tarlib.Errors.OK;
      elsif Split.Status.Code = Tarlib.Errors.Path_Too_Long then
         Append_PAX_Record (PAX, "path", Path, Result);
         if Result.Code /= Tarlib.Errors.Success then
            Last := Header_Path'First - 1;
            return;
         end if;

         Header_Path (Header_Path'First .. Header_Path'First + 8) :=
           "pax-entry";
         Last := Header_Path'First + 8;
         Result := Tarlib.Errors.OK;
      else
         Result := Split.Status;
         Last := Header_Path'First - 1;
      end if;
   end Prepare_Header_Path;

   procedure Initialize
     (Archive     : in out Writer;
      Destination : aliased in out Tarlib.Outputs.Output_Sink'Class;
      Result      : out Tarlib.Errors.Status) is
   begin
      if Archive.Current_State /= Uninitialized then
         Result := (Code => Tarlib.Errors.Invalid_State);
         return;
      end if;

      Archive.Destination := Destination'Unchecked_Access;
      Archive.Current_State := Ready;
      Archive.Declared_Size := 0;
      Archive.Written_Size := 0;
      Result := Tarlib.Errors.OK;
   end Initialize;

   procedure Begin_Entry
     (Archive  : in out Writer;
      Path     : String;
      Kind     : Tarlib.Entries.Entry_Kind;
      Size     : Tarlib.Byte_Count;
      Metadata : Tarlib.Entries.Metadata;
      Result   : out Tarlib.Errors.Status)
   is
      Header : Tarlib.Internal.Constants.Header_Block;
      Header_Path : String (1 .. 100);
      Header_Path_Last : Natural;
      Header_Size : Tarlib.Byte_Count := Size;
      Header_Metadata : Tarlib.Entries.Metadata := Metadata;
      PAX : PAX_Buffer;
   begin
      if Archive.Current_State = Failed then
         Result := (Code => Tarlib.Errors.Output_Failure);
         return;
      elsif Archive.Current_State = Finished then
         Result := (Code => Tarlib.Errors.Already_Finished);
         return;
      elsif Archive.Current_State /= Ready then
         Result := (Code => Tarlib.Errors.Invalid_State);
         return;
      elsif Kind not in Tarlib.Entries.Regular_File
                      | Tarlib.Entries.Directory
                      | Tarlib.Entries.Multi_Volume
                      | Tarlib.Entries.Incremental_Dump
                      | Tarlib.Entries.Volume_Label
      then
         Result := (Code => Tarlib.Errors.Invalid_Entry_Kind);
         return;
      elsif Kind in Tarlib.Entries.Directory | Tarlib.Entries.Volume_Label
        and then Size /= 0
      then
         Result := (Code => Tarlib.Errors.Invalid_Size);
         return;
      end if;

      Prepare_Header_Path
        (PAX, Path, Header_Path, Header_Path_Last, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      if Kind = Tarlib.Entries.Regular_File and then Size > Tarlib.USTAR_Size_Max then
         Append_PAX_Size (PAX, Size, Result);
         if Result.Code /= Tarlib.Errors.Success then
            return;
         end if;
         Header_Size := 0;
      end if;

      Append_PAX_Metadata (PAX, Metadata, Header_Metadata, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Write_PAX_Records (Archive, PAX, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Tarlib.Internal.Headers.Build
        (Header_Path (1 .. Header_Path_Last), Kind, Header_Size,
         Header_Metadata, Header, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Write_Block (Archive, Header, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Archive.Current_State := Writing_Entry;
      Archive.Active_Kind := Kind;
      Archive.Declared_Size := Size;
      Archive.Written_Size := 0;
   end Begin_Entry;

   procedure Begin_File
     (Archive  : in out Writer;
      Path     : String;
      Size     : Tarlib.Byte_Count;
      Result   : out Tarlib.Errors.Status)
   is
   begin
      Begin_Entry
        (Archive, Path, Tarlib.Entries.Regular_File, Size,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File), Result);
   end Begin_File;

   procedure Begin_Sparse_File
     (Archive      : in out Writer;
      Path         : String;
      Logical_Size : Tarlib.Byte_Count;
      Extents      : Tarlib.Entries.Sparse_Extent_Array;
      Format       : Sparse_Format;
      Metadata     : Tarlib.Entries.Metadata;
      Result       : out Tarlib.Errors.Status)
   is
      Header : Tarlib.Internal.Constants.Header_Block;
      Header_Path : String (1 .. 100);
      Header_Path_Last : Natural;
      Header_Metadata : Tarlib.Entries.Metadata := Metadata;
      Physical_Size : Tarlib.Byte_Count;
      PAX : PAX_Buffer;
      Extension_Index : Positive;
   begin
      if Archive.Current_State = Failed then
         Result := (Code => Tarlib.Errors.Output_Failure);
         return;
      elsif Archive.Current_State = Finished then
         Result := (Code => Tarlib.Errors.Already_Finished);
         return;
      elsif Archive.Current_State /= Ready then
         Result := (Code => Tarlib.Errors.Invalid_State);
         return;
      end if;

      Validate_Sparse_Extents (Logical_Size, Extents, Physical_Size, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Prepare_Header_Path
        (PAX, Path, Header_Path, Header_Path_Last, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      if Format = GNU_PAX_Sparse then
         Append_PAX_Record
           (PAX, "GNU.sparse.size",
            Decimal_Text (Interfaces.Unsigned_64 (Logical_Size)), Result);
         if Result.Code /= Tarlib.Errors.Success then
            return;
         end if;
         Append_PAX_Record
           (PAX, "GNU.sparse.map", Sparse_Map_Text (Extents), Result);
         if Result.Code /= Tarlib.Errors.Success then
            return;
         end if;
      elsif Format = Star_PAX_Sparse then
         Append_PAX_Record (PAX, "SCHILY.filetype", "sparse", Result);
         if Result.Code /= Tarlib.Errors.Success then
            return;
         end if;
         Append_PAX_Record
           (PAX, "SCHILY.realsize",
            Decimal_Text (Interfaces.Unsigned_64 (Logical_Size)), Result);
         if Result.Code /= Tarlib.Errors.Success then
            return;
         end if;
         for Extent of Extents loop
            Append_PAX_Record
              (PAX, "SCHILY.offset",
               Decimal_Text (Interfaces.Unsigned_64 (Extent.Offset)), Result);
            if Result.Code /= Tarlib.Errors.Success then
               return;
            end if;
            Append_PAX_Record
              (PAX, "SCHILY.numbytes",
               Decimal_Text (Interfaces.Unsigned_64 (Extent.Length)), Result);
            if Result.Code /= Tarlib.Errors.Success then
               return;
            end if;
         end loop;
      elsif Format = Libarchive_PAX_Sparse then
         Append_PAX_Record (PAX, "LIBARCHIVE.sparse", "1", Result);
         if Result.Code /= Tarlib.Errors.Success then
            return;
         end if;
         Append_PAX_Record
           (PAX, "LIBARCHIVE.sparse.size",
            Decimal_Text (Interfaces.Unsigned_64 (Logical_Size)), Result);
         if Result.Code /= Tarlib.Errors.Success then
            return;
         end if;
         for Extent of Extents loop
            Append_PAX_Record
              (PAX, "LIBARCHIVE.sparse.offset",
               Decimal_Text (Interfaces.Unsigned_64 (Extent.Offset)), Result);
            if Result.Code /= Tarlib.Errors.Success then
               return;
            end if;
            Append_PAX_Record
              (PAX, "LIBARCHIVE.sparse.numbytes",
               Decimal_Text (Interfaces.Unsigned_64 (Extent.Length)), Result);
            if Result.Code /= Tarlib.Errors.Success then
               return;
            end if;
         end loop;
      end if;

      Append_PAX_Metadata (PAX, Metadata, Header_Metadata, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      if Format /= Old_GNU_Sparse then
         Write_PAX_Records (Archive, PAX, Result);
         if Result.Code /= Tarlib.Errors.Success then
            return;
         end if;

         Tarlib.Internal.Headers.Build
           (Header_Path (1 .. Header_Path_Last), Tarlib.Entries.Regular_File,
            Physical_Size, Header_Metadata, Header, Result);
      else
         if PAX.Last /= 0 then
            Result := (Code => Tarlib.Errors.Invalid_Metadata);
            return;
         end if;

         Tarlib.Internal.Headers.Build
           (Header_Path (1 .. Header_Path_Last), Tarlib.Entries.GNU_Sparse,
            Physical_Size, Header_Metadata, Header, Result);
      end if;
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      if Format = Old_GNU_Sparse then
         Header (263) := Character'Pos (' ');
         Header (264) := Character'Pos (' ');
         Header (265) := 0;
         for Slot in 1 .. Natural'Min (Extents'Length, 4) loop
            Put_Sparse_Extent
              (Header,
               387 + Ada.Streams.Stream_Element_Offset ((Slot - 1) * 24),
               Extents (Extents'First + Slot - 1), Result);
            if Result.Code /= Tarlib.Errors.Success then
               return;
            end if;
         end loop;
         Header (483) := (if Extents'Length > 4 then 1 else 0);
         Tarlib.Internal.Fields.Put_Octal
           (Header (484 .. 495), Interfaces.Unsigned_64 (Logical_Size),
            Tarlib.Internal.Fields.NUL_Terminated, Result);
         if Result.Code /= Tarlib.Errors.Success then
            return;
         end if;
         Header (149 .. 156) := [others => 32];
         Tarlib.Internal.Fields.Put_Octal
           (Header (149 .. 156), Tarlib.Internal.Checksums.Compute (Header),
            Tarlib.Internal.Fields.Checksum_Terminated, Result);
         if Result.Code /= Tarlib.Errors.Success then
            return;
         end if;
      end if;

      Write_Block (Archive, Header, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      if Format = Old_GNU_Sparse and then Extents'Length > 4 then
         Extension_Index := Extents'First + 4;
         while Extension_Index <= Extents'Last loop
            declare
               Extension : Tarlib.Internal.Constants.Header_Block :=
                 [others => 0];
            begin
               for Slot in 1 .. 21 loop
                  exit when Extension_Index > Extents'Last;
                  Put_Sparse_Extent
                    (Extension,
                     1 + Ada.Streams.Stream_Element_Offset ((Slot - 1) * 24),
                     Extents (Extension_Index), Result);
                  if Result.Code /= Tarlib.Errors.Success then
                     return;
                  end if;
                  Extension_Index := Extension_Index + 1;
               end loop;
               Extension (505) :=
                 (if Extension_Index <= Extents'Last then 1 else 0);
               Write_Block (Archive, Extension, Result);
               if Result.Code /= Tarlib.Errors.Success then
                  return;
               end if;
            end;
         end loop;
      end if;

      Archive.Current_State := Writing_Entry;
      Archive.Active_Kind := Tarlib.Entries.Regular_File;
      Archive.Declared_Size := Physical_Size;
      Archive.Written_Size := 0;
   end Begin_Sparse_File;

   procedure Begin_Sparse_File
     (Archive      : in out Writer;
      Path         : String;
      Logical_Size : Tarlib.Byte_Count;
      Extents      : Tarlib.Entries.Sparse_Extent_Array;
      Metadata     : Tarlib.Entries.Metadata;
      Result       : out Tarlib.Errors.Status)
   is
   begin
      Begin_Sparse_File
        (Archive, Path, Logical_Size, Extents, GNU_PAX_Sparse, Metadata,
         Result);
   end Begin_Sparse_File;

   procedure Begin_Sparse_File
     (Archive      : in out Writer;
      Path         : String;
      Logical_Size : Tarlib.Byte_Count;
      Extents      : Tarlib.Entries.Sparse_Extent_Array;
      Result       : out Tarlib.Errors.Status)
   is
   begin
      Begin_Sparse_File
        (Archive, Path, Logical_Size, Extents, GNU_PAX_Sparse,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File),
         Result);
   end Begin_Sparse_File;

   procedure Add_Directory
     (Archive : in out Writer;
      Path    : String;
      Result  : out Tarlib.Errors.Status) is
   begin
      Begin_Entry
        (Archive, Path, Tarlib.Entries.Directory, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Directory), Result);
      if Result.Code = Tarlib.Errors.Success then
         End_Entry (Archive, Result);
      end if;
   end Add_Directory;

   procedure Add_Link
     (Archive   : in out Writer;
      Path      : String;
      Kind      : Tarlib.Entries.Entry_Kind;
      Link_Path : String;
      Metadata  : Tarlib.Entries.Metadata;
      Result    : out Tarlib.Errors.Status)
   is
      Header : Tarlib.Internal.Constants.Header_Block;
      Header_Path : String (1 .. 100);
      Header_Path_Last : Natural;
      Header_Link_Path : constant String :=
        (if Link_Path'Length <= 100 then Link_Path else "pax-link-target");
      PAX : PAX_Buffer;
      Header_Metadata : Tarlib.Entries.Metadata := Metadata;
      Hard_Link_Target : Tarlib.Errors.Status;
   begin
      if Kind not in Tarlib.Entries.Hard_Link | Tarlib.Entries.Symbolic_Link then
         Result := (Code => Tarlib.Errors.Invalid_Entry_Kind);
         return;
      elsif Archive.Current_State = Failed then
         Result := (Code => Tarlib.Errors.Output_Failure);
         return;
      elsif Archive.Current_State = Finished then
         Result := (Code => Tarlib.Errors.Already_Finished);
         return;
      elsif Archive.Current_State /= Ready then
         Result := (Code => Tarlib.Errors.Invalid_State);
         return;
      elsif Link_Path'Length = 0 then
         Result := (Code => Tarlib.Errors.Invalid_Metadata);
         return;
      end if;

      if Contains_NUL (Link_Path) then
         Result := (Code => Tarlib.Errors.Invalid_Metadata);
         return;
      elsif Kind = Tarlib.Entries.Hard_Link and then Link_Path'Length > 0 then
         Hard_Link_Target :=
           Tarlib.Internal.Paths.Validate_Archive_Path (Link_Path);
         if Hard_Link_Target.Code /= Tarlib.Errors.Success then
            Result := Hard_Link_Target;
            return;
         end if;
      end if;

      if Link_Path'Length > 100 then
         Append_PAX_Record (PAX, "linkpath", Link_Path, Result);
         if Result.Code /= Tarlib.Errors.Success then
            return;
         end if;
      end if;

      Prepare_Header_Path
        (PAX, Path, Header_Path, Header_Path_Last, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Append_PAX_Metadata (PAX, Metadata, Header_Metadata, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Write_PAX_Records (Archive, PAX, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Tarlib.Internal.Headers.Build
        (Header_Path (1 .. Header_Path_Last), Kind, 0, Header_Metadata,
         Header_Link_Path, Header, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Write_Block (Archive, Header, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Archive.Current_State := Ready;
      Archive.Active_Kind := Kind;
      Archive.Declared_Size := 0;
      Archive.Written_Size := 0;
      Result := Tarlib.Errors.OK;
   end Add_Link;

   procedure Add_Hard_Link
     (Archive   : in out Writer;
      Path      : String;
      Link_Path : String;
      Result    : out Tarlib.Errors.Status) is
   begin
      Add_Link
        (Archive, Path, Tarlib.Entries.Hard_Link, Link_Path,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Hard_Link), Result);
   end Add_Hard_Link;

   procedure Add_Symbolic_Link
     (Archive   : in out Writer;
      Path      : String;
      Link_Path : String;
      Result    : out Tarlib.Errors.Status) is
   begin
      Add_Link
        (Archive, Path, Tarlib.Entries.Symbolic_Link, Link_Path,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Symbolic_Link),
         Result);
   end Add_Symbolic_Link;

   procedure Add_Special
     (Archive  : in out Writer;
      Path     : String;
      Kind     : Tarlib.Entries.Entry_Kind;
      Device   : Tarlib.Entries.Device_Numbers;
      Metadata : Tarlib.Entries.Metadata;
      Result   : out Tarlib.Errors.Status)
   is
      Header : Tarlib.Internal.Constants.Header_Block;
      Header_Path : String (1 .. 100);
      Header_Path_Last : Natural;
      PAX : PAX_Buffer;
      Header_Metadata : Tarlib.Entries.Metadata := Metadata;
   begin
      if Kind not in Tarlib.Entries.Character_Device
                   | Tarlib.Entries.Block_Device
                   | Tarlib.Entries.FIFO
      then
         Result := (Code => Tarlib.Errors.Invalid_Entry_Kind);
         return;
      elsif Archive.Current_State = Failed then
         Result := (Code => Tarlib.Errors.Output_Failure);
         return;
      elsif Archive.Current_State = Finished then
         Result := (Code => Tarlib.Errors.Already_Finished);
         return;
      elsif Archive.Current_State /= Ready then
         Result := (Code => Tarlib.Errors.Invalid_State);
         return;
      elsif Kind not in Tarlib.Entries.Character_Device
                       | Tarlib.Entries.Block_Device
        and then (Device.Major /= 0 or else Device.Minor /= 0)
      then
         Result := (Code => Tarlib.Errors.Invalid_Metadata);
         return;
      end if;

      Prepare_Header_Path
        (PAX, Path, Header_Path, Header_Path_Last, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Append_PAX_Metadata (PAX, Metadata, Header_Metadata, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Write_PAX_Records (Archive, PAX, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Tarlib.Internal.Headers.Build
        (Header_Path (1 .. Header_Path_Last), Kind, 0, Header_Metadata, "", Device,
         Header, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Write_Block (Archive, Header, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Archive.Current_State := Ready;
      Archive.Active_Kind := Kind;
      Archive.Declared_Size := 0;
      Archive.Written_Size := 0;
      Result := Tarlib.Errors.OK;
   end Add_Special;

   procedure Add_Character_Device
     (Archive : in out Writer;
      Path    : String;
      Device  : Tarlib.Entries.Device_Numbers;
      Result  : out Tarlib.Errors.Status) is
   begin
      Add_Special
        (Archive, Path, Tarlib.Entries.Character_Device, Device,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Character_Device),
         Result);
   end Add_Character_Device;

   procedure Add_Block_Device
     (Archive : in out Writer;
      Path    : String;
      Device  : Tarlib.Entries.Device_Numbers;
      Result  : out Tarlib.Errors.Status) is
   begin
      Add_Special
        (Archive, Path, Tarlib.Entries.Block_Device, Device,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Block_Device), Result);
   end Add_Block_Device;

   procedure Add_FIFO
     (Archive : in out Writer;
      Path    : String;
      Result  : out Tarlib.Errors.Status) is
   begin
      Add_Special
        (Archive, Path, Tarlib.Entries.FIFO, Tarlib.Entries.No_Device,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.FIFO), Result);
   end Add_FIFO;

   procedure Add_Extended_Record
     (Archive : in out Writer;
      Keyword : String;
      Value   : String;
      Result  : out Tarlib.Errors.Status)
   is
      PAX : PAX_Buffer;
   begin
      if Archive.Current_State = Failed then
         Result := (Code => Tarlib.Errors.Output_Failure);
         return;
      elsif Archive.Current_State = Finished then
         Result := (Code => Tarlib.Errors.Already_Finished);
         return;
      elsif Archive.Current_State /= Ready then
         Result := (Code => Tarlib.Errors.Invalid_State);
         return;
      end if;

      Append_PAX_Record (PAX, Keyword, Value, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Write_PAX_Records (Archive, PAX, Result);
   end Add_Extended_Record;

   procedure Write
     (Archive : in out Writer;
      Data    : Ada.Streams.Stream_Element_Array;
      Result  : out Tarlib.Errors.Status)
   is
      Length : constant Interfaces.Unsigned_64 :=
        Interfaces.Unsigned_64 (Data'Length);
   begin
      if Archive.Current_State = Failed then
         Result := (Code => Tarlib.Errors.Output_Failure);
         return;
      elsif Archive.Current_State = Finished then
         Result := (Code => Tarlib.Errors.Already_Finished);
         return;
      elsif Archive.Current_State /= Writing_Entry then
         Result := (Code => Tarlib.Errors.Invalid_State);
         return;
      elsif Archive.Active_Kind not in Tarlib.Entries.Regular_File
                                   | Tarlib.Entries.Multi_Volume
                                   | Tarlib.Entries.Incremental_Dump
      then
         Result := (Code => Tarlib.Errors.Invalid_Entry_Kind);
         return;
      elsif Length > Archive.Declared_Size - Archive.Written_Size then
         Result := (Code => Tarlib.Errors.Too_Much_Entry_Data);
         return;
      end if;

      if Data'Length > 0 then
         Archive.Destination.Write (Data, Result);
         Mark_Output_Failure (Archive, Result);
         if Result.Code /= Tarlib.Errors.Success then
            return;
         end if;
      end if;

      Archive.Written_Size := Archive.Written_Size + Length;
      Result := Tarlib.Errors.OK;
   end Write;

   procedure End_Entry
     (Archive : in out Writer;
      Result  : out Tarlib.Errors.Status)
   is
      Padding : constant Natural :=
        Tarlib.Internal.Padding.Padding_Length (Archive.Declared_Size);
      Block   : constant Tarlib.Internal.Constants.Header_Block :=
        Tarlib.Internal.Constants.Zero_Block;
   begin
      if Archive.Current_State = Failed then
         Result := (Code => Tarlib.Errors.Output_Failure);
         return;
      elsif Archive.Current_State = Finished then
         Result := (Code => Tarlib.Errors.Already_Finished);
         return;
      elsif Archive.Current_State /= Writing_Entry then
         Result := (Code => Tarlib.Errors.Invalid_State);
         return;
      elsif Archive.Written_Size < Archive.Declared_Size then
         Result := (Code => Tarlib.Errors.Too_Little_Entry_Data);
         return;
      end if;

      if Padding > 0 then
         Archive.Destination.Write
           (Ada.Streams.Stream_Element_Array
              (Block (1 .. Ada.Streams.Stream_Element_Offset (Padding))),
            Result);
         Mark_Output_Failure (Archive, Result);
         if Result.Code /= Tarlib.Errors.Success then
            return;
         end if;
      end if;

      Archive.Current_State := Ready;
      Archive.Declared_Size := 0;
      Archive.Written_Size := 0;
      Result := Tarlib.Errors.OK;
   end End_Entry;

   procedure Finish
     (Archive : in out Writer;
      Result  : out Tarlib.Errors.Status) is
   begin
      if Archive.Current_State = Failed then
         Result := (Code => Tarlib.Errors.Output_Failure);
         return;
      elsif Archive.Current_State = Finished then
         Result := (Code => Tarlib.Errors.Already_Finished);
         return;
      elsif Archive.Current_State /= Ready then
         Result := (Code => Tarlib.Errors.Invalid_State);
         return;
      end if;

      Write_Block (Archive, Tarlib.Internal.Constants.Zero_Block, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Write_Block (Archive, Tarlib.Internal.Constants.Zero_Block, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Archive.Current_State := Finished;
      Result := Tarlib.Errors.OK;
   end Finish;

   function State (Archive : Writer) return Writer_State is
   begin
      return Archive.Current_State;
   end State;
end Tarlib.Writers;
