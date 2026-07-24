with Ada.Streams;
with Interfaces;
with Tarlib.Internal.Checksums;
with Tarlib.Internal.Fields;
with Tarlib.Internal.Paths;

package body Tarlib.Internal.Headers is
   use type Ada.Streams.Stream_Element_Offset;
   use type Ada.Streams.Stream_Element;
   use type Interfaces.Integer_64;
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;
   use type Tarlib.Entries.Entry_Kind;
   use type Tarlib.Errors.Status_Code;

   procedure Put_Bytes
     (Header : in out Tarlib.Internal.Constants.Header_Block;
      First  : Ada.Streams.Stream_Element_Offset;
      Text   : String;
      Result : out Tarlib.Errors.Status)
   is
      Last : constant Ada.Streams.Stream_Element_Offset :=
        First + Ada.Streams.Stream_Element_Offset (Text'Length) - 1;
   begin
      Tarlib.Internal.Fields.Put_String (Header (First .. Last), Text, Result);
   end Put_Bytes;

   procedure Build
     (Path     : String;
      Kind     : Tarlib.Entries.Entry_Kind;
      Size     : Tarlib.Byte_Count;
      Metadata : Tarlib.Entries.Metadata;
      Header   : out Tarlib.Internal.Constants.Header_Block;
      Result   : out Tarlib.Errors.Status) is
   begin
      Build (Path, Kind, Size, Metadata, "", Header, Result);
   end Build;

   procedure Build
     (Path      : String;
      Kind      : Tarlib.Entries.Entry_Kind;
      Size      : Tarlib.Byte_Count;
      Metadata  : Tarlib.Entries.Metadata;
      Link_Path : String;
      Header    : out Tarlib.Internal.Constants.Header_Block;
      Result   : out Tarlib.Errors.Status)
   is
   begin
      Build
        (Path, Kind, Size, Metadata, Link_Path, Tarlib.Entries.No_Device,
         Header, Result);
   end Build;

   procedure Build
     (Path      : String;
      Kind      : Tarlib.Entries.Entry_Kind;
      Size      : Tarlib.Byte_Count;
      Metadata  : Tarlib.Entries.Metadata;
      Link_Path : String;
      Device    : Tarlib.Entries.Device_Numbers;
      Header    : out Tarlib.Internal.Constants.Header_Block;
      Result   : out Tarlib.Errors.Status)
   is
      Split    : constant Tarlib.Internal.Paths.Path_Split :=
        Tarlib.Internal.Paths.Split (Path);
      Checksum : Tarlib.Internal.Checksums.Checksum_Value;
   begin
      Header := [others => 0];

      if Split.Status.Code /= Tarlib.Errors.Success then
         Result := Split.Status;
         return;
      end if;

      if Kind in Tarlib.Entries.Directory
              | Tarlib.Entries.Hard_Link
              | Tarlib.Entries.Symbolic_Link
              | Tarlib.Entries.Character_Device
              | Tarlib.Entries.Block_Device
              | Tarlib.Entries.FIFO
              | Tarlib.Entries.Volume_Label
        and then Size /= 0
      then
         Result := (Code => Tarlib.Errors.Invalid_Size);
         return;
      elsif Kind in Tarlib.Entries.Hard_Link | Tarlib.Entries.Symbolic_Link
        and then Link_Path'Length = 0
      then
         Result := (Code => Tarlib.Errors.Invalid_Metadata);
         return;
      elsif Kind not in Tarlib.Entries.Character_Device
                       | Tarlib.Entries.Block_Device
        and then (Device.Major /= 0 or else Device.Minor /= 0)
      then
         Result := (Code => Tarlib.Errors.Invalid_Metadata);
         return;
      end if;

      Tarlib.Internal.Fields.Put_String
        (Header (1 .. 100), Path (Split.Name_First .. Split.Name_Last), Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Tarlib.Internal.Fields.Put_Octal
        (Header (101 .. 108), Interfaces.Unsigned_64 (Metadata.Mode),
         Tarlib.Internal.Fields.NUL_Terminated, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Tarlib.Internal.Fields.Put_Octal
        (Header (109 .. 116), Interfaces.Unsigned_64 (Metadata.UID),
         Tarlib.Internal.Fields.NUL_Terminated, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Tarlib.Internal.Fields.Put_Octal
        (Header (117 .. 124), Interfaces.Unsigned_64 (Metadata.GID),
         Tarlib.Internal.Fields.NUL_Terminated, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Tarlib.Internal.Fields.Put_Octal
        (Header (125 .. 136), Interfaces.Unsigned_64 (Size),
         Tarlib.Internal.Fields.NUL_Terminated, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      if Metadata.MTime < 0 then
         Result := (Code => Tarlib.Errors.Invalid_Metadata);
         return;
      end if;

      Tarlib.Internal.Fields.Put_Octal
        (Header (137 .. 148), Interfaces.Unsigned_64 (Metadata.MTime),
         Tarlib.Internal.Fields.NUL_Terminated, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Header (149 .. 156) := [others => 32];
      Header (157) :=
        (case Kind is
            when Tarlib.Entries.Regular_File => Character'Pos ('0'),
            when Tarlib.Entries.Hard_Link    => Character'Pos ('1'),
            when Tarlib.Entries.Symbolic_Link => Character'Pos ('2'),
            when Tarlib.Entries.Character_Device => Character'Pos ('3'),
            when Tarlib.Entries.Block_Device => Character'Pos ('4'),
            when Tarlib.Entries.FIFO         => Character'Pos ('6'),
            when Tarlib.Entries.PAX_Extended_Header => Character'Pos ('x'),
            when Tarlib.Entries.PAX_Global_Header => Character'Pos ('g'),
            when Tarlib.Entries.GNU_Long_Name => Character'Pos ('L'),
            when Tarlib.Entries.GNU_Long_Link => Character'Pos ('K'),
            when Tarlib.Entries.GNU_Sparse    => Character'Pos ('S'),
            when Tarlib.Entries.Volume_Label  => Character'Pos ('V'),
            when Tarlib.Entries.Multi_Volume  => Character'Pos ('M'),
            when Tarlib.Entries.Incremental_Dump => Character'Pos ('D'),
            when Tarlib.Entries.Directory    => Character'Pos ('5'));
      Tarlib.Internal.Fields.Put_String
        (Header (158 .. 257), Link_Path, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;
      Put_Bytes (Header, 258, "ustar", Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;
      Header (263) := 0;
      Header (264) := Character'Pos ('0');
      Header (265) := Character'Pos ('0');
      Header (266 .. 329) := [others => 0];
      Tarlib.Internal.Fields.Put_String
        (Header (266 .. 297), Tarlib.Entries.Text (Metadata.User_Name),
         Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Tarlib.Internal.Fields.Put_String
        (Header (298 .. 329), Tarlib.Entries.Text (Metadata.Group_Name),
         Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Tarlib.Internal.Fields.Put_Octal
        (Header (330 .. 337), Interfaces.Unsigned_64 (Device.Major),
         Tarlib.Internal.Fields.NUL_Terminated, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Tarlib.Internal.Fields.Put_Octal
        (Header (338 .. 345), Interfaces.Unsigned_64 (Device.Minor),
         Tarlib.Internal.Fields.NUL_Terminated, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      if Split.Prefix_Length > 0 then
         Tarlib.Internal.Fields.Put_String
           (Header (346 .. 500),
            Path (Split.Prefix_First .. Split.Prefix_Last), Result);
         if Result.Code /= Tarlib.Errors.Success then
            return;
         end if;
      end if;

      Checksum := Tarlib.Internal.Checksums.Compute (Header);
      Tarlib.Internal.Fields.Put_Octal
        (Header (149 .. 156), Checksum,
         Tarlib.Internal.Fields.Checksum_Terminated, Result);
   end Build;

   function Matches_Text
     (Header : Tarlib.Internal.Constants.Header_Block;
      First  : Ada.Streams.Stream_Element_Offset;
      Text   : String) return Boolean
   is
   begin
      for Offset in 0 .. Text'Length - 1 loop
         if Header
              (First + Ada.Streams.Stream_Element_Offset (Offset))
            /= Ada.Streams.Stream_Element
                 (Character'Pos (Text (Text'First + Offset)))
         then
            return False;
         end if;
      end loop;

      return True;
   end Matches_Text;

   function Is_Zero_Range
     (Header : Tarlib.Internal.Constants.Header_Block;
      First  : Ada.Streams.Stream_Element_Offset;
      Last   : Ada.Streams.Stream_Element_Offset) return Boolean is
   begin
      for Index in First .. Last loop
         if Header (Index) /= 0 then
            return False;
         end if;
      end loop;

      return True;
   end Is_Zero_Range;

   procedure Copy_Text
     (Header : Tarlib.Internal.Constants.Header_Block;
      First  : Ada.Streams.Stream_Element_Offset;
      Length : Natural;
      Target : in out String;
      Cursor : in out Natural)
   is
   begin
      for Offset in 0 .. Length - 1 loop
         Cursor := Cursor + 1;
         Target (Cursor) :=
           Character'Val
             (Header (First + Ada.Streams.Stream_Element_Offset (Offset)));
      end loop;
   end Copy_Text;

   procedure Parse_Old_GNU_Sparse
     (Header : Tarlib.Internal.Constants.Header_Block;
      Parsed : in out Parsed_Header;
      Result : out Tarlib.Errors.Status)
   is
      Offset_Value : Interfaces.Unsigned_64;
      Length_Value : Interfaces.Unsigned_64;
      Real_Size    : Interfaces.Unsigned_64;
      First        : Ada.Streams.Stream_Element_Offset := 387;
   begin
      Parsed.Sparse_Count := 0;
      for Slot in 1 .. Max_Header_Sparse_Extents loop
         if not Is_Zero_Range (Header, First, First + 23) then
            Tarlib.Internal.Fields.Get_Numeric
              (Header (First .. First + 11), Offset_Value, Result);
            if Result.Code /= Tarlib.Errors.Success then
               return;
            end if;
            Tarlib.Internal.Fields.Get_Numeric
              (Header (First + 12 .. First + 23), Length_Value, Result);
            if Result.Code /= Tarlib.Errors.Success then
               return;
            end if;

            Parsed.Sparse_Count := Slot;
            Parsed.Sparse_Extents (Slot) :=
              (Offset => Tarlib.Byte_Count (Offset_Value),
               Length => Tarlib.Byte_Count (Length_Value));
         end if;

         First := First + 24;
      end loop;

      Parsed.Has_Sparse_Extension := Header (483) /= 0;

      if Parsed.Sparse_Count = 0 then
         Result := (Code => Tarlib.Errors.Invalid_Entry_Kind);
         return;
      end if;

      Tarlib.Internal.Fields.Get_Numeric
        (Header (484 .. 495), Real_Size, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Parsed.Sparse_Size := Tarlib.Byte_Count (Real_Size);
      Parsed.Has_Sparse_Map := True;
      Result := Tarlib.Errors.OK;
   end Parse_Old_GNU_Sparse;

   procedure Parse
     (Header : Tarlib.Internal.Constants.Header_Block;
      Parsed : out Parsed_Header;
      Result : out Tarlib.Errors.Status)
   is
      Stored_Checksum : Interfaces.Unsigned_64;
      Computed        : constant Tarlib.Internal.Checksums.Checksum_Value :=
        Tarlib.Internal.Checksums.Compute (Header);
      Signed_Computed : constant Interfaces.Integer_64 :=
        Tarlib.Internal.Checksums.Compute_Signed (Header);
      Name_Length     : constant Natural :=
        Tarlib.Internal.Fields.Text_Length (Header (1 .. 100));
      Prefix_Length   : constant Natural :=
        Tarlib.Internal.Fields.Text_Length (Header (346 .. 500));
      Size_Value      : Interfaces.Unsigned_64;
      Mode_Value      : Interfaces.Unsigned_64;
      UID_Value       : Interfaces.Unsigned_64;
      GID_Value       : Interfaces.Unsigned_64;
      MTime_Value     : Interfaces.Unsigned_64;
      Major_Value     : Interfaces.Unsigned_64;
      Minor_Value     : Interfaces.Unsigned_64;
      User_Length     : constant Natural :=
        Tarlib.Internal.Fields.Text_Length (Header (266 .. 297));
      Group_Length    : constant Natural :=
        Tarlib.Internal.Fields.Text_Length (Header (298 .. 329));
      Offset_Value    : Interfaces.Unsigned_64;
      Cursor          : Natural := 0;
      Is_POSIX_USTAR  : constant Boolean :=
        Matches_Text (Header, 258, "ustar")
        and then Header (263) = 0
        and then Header (264) = Character'Pos ('0')
        and then Header (265) = Character'Pos ('0');
      Is_Old_GNU      : constant Boolean :=
        Matches_Text (Header, 258, "ustar")
        and then Header (263) = Character'Pos (' ')
        and then Header (264) = Character'Pos (' ')
        and then Header (265) = 0;
      Is_USTAR        : constant Boolean := Is_POSIX_USTAR or else Is_Old_GNU;
      Is_Legacy       : constant Boolean :=
        Is_Zero_Range (Header, 258, 345);
   begin
      Parsed := (others => <>);

      Tarlib.Internal.Fields.Get_Octal
        (Header (149 .. 156), Stored_Checksum, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      elsif Stored_Checksum /= Computed
        and then
          (Signed_Computed < 0
           or else Stored_Checksum /= Interfaces.Unsigned_64 (Signed_Computed))
      then
         Result := (Code => Tarlib.Errors.Invalid_Archive);
         return;
      end if;

      if not Is_USTAR and then not Is_Legacy then
         Result := (Code => Tarlib.Errors.Invalid_Archive);
         return;
      end if;

      if Name_Length = 0 then
         Result := (Code => Tarlib.Errors.Invalid_Path);
         return;
      end if;

      Tarlib.Internal.Fields.Get_Numeric
        (Header (101 .. 108), Mode_Value, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      elsif Mode_Value > Interfaces.Unsigned_64 (Tarlib.Entries.File_Mode'Last) then
         Result := (Code => Tarlib.Errors.Invalid_Metadata);
         return;
      end if;

      Tarlib.Internal.Fields.Get_Numeric
        (Header (109 .. 116), UID_Value, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Tarlib.Internal.Fields.Get_Numeric
        (Header (117 .. 124), GID_Value, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Tarlib.Internal.Fields.Get_Numeric
        (Header (125 .. 136), Size_Value, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Tarlib.Internal.Fields.Get_Numeric
        (Header (137 .. 148), MTime_Value, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      elsif MTime_Value > Interfaces.Unsigned_64 (Tarlib.Entries.Timestamp'Last) then
         Result := (Code => Tarlib.Errors.Invalid_Metadata);
         return;
      end if;

      Parsed.Kind :=
        (case Header (157) is
            when 0 | Character'Pos ('0')  => Tarlib.Entries.Regular_File,
            when Character'Pos ('1')      => Tarlib.Entries.Hard_Link,
            when Character'Pos ('2')      => Tarlib.Entries.Symbolic_Link,
            when Character'Pos ('3')      => Tarlib.Entries.Character_Device,
            when Character'Pos ('4')      => Tarlib.Entries.Block_Device,
            when Character'Pos ('5')      => Tarlib.Entries.Directory,
            when Character'Pos ('6')      => Tarlib.Entries.FIFO,
            when Character'Pos ('7')      => Tarlib.Entries.Regular_File,
            when Character'Pos ('x')      => Tarlib.Entries.PAX_Extended_Header,
            when Character'Pos ('g')      => Tarlib.Entries.PAX_Global_Header,
            when Character'Pos ('L')      => Tarlib.Entries.GNU_Long_Name,
            when Character'Pos ('K')      => Tarlib.Entries.GNU_Long_Link,
            when Character'Pos ('S')      => Tarlib.Entries.GNU_Sparse,
            when Character'Pos ('V')      => Tarlib.Entries.Volume_Label,
            when Character'Pos ('M')      => Tarlib.Entries.Multi_Volume,
            when Character'Pos ('D')      => Tarlib.Entries.Incremental_Dump,
            when others                   => Tarlib.Entries.Regular_File);
      if Header (157) /= 0
        and then Header (157) /= Character'Pos ('0')
        and then Header (157) /= Character'Pos ('1')
        and then Header (157) /= Character'Pos ('2')
        and then Header (157) /= Character'Pos ('3')
        and then Header (157) /= Character'Pos ('4')
        and then Header (157) /= Character'Pos ('5')
        and then Header (157) /= Character'Pos ('6')
        and then Header (157) /= Character'Pos ('7')
        and then Header (157) /= Character'Pos ('x')
        and then Header (157) /= Character'Pos ('g')
        and then Header (157) /= Character'Pos ('L')
        and then Header (157) /= Character'Pos ('K')
        and then Header (157) /= Character'Pos ('S')
        and then Header (157) /= Character'Pos ('V')
        and then Header (157) /= Character'Pos ('M')
        and then Header (157) /= Character'Pos ('D')
      then
         Result := (Code => Tarlib.Errors.Invalid_Entry_Kind);
         return;
      elsif Parsed.Kind in Tarlib.Entries.Directory
                         | Tarlib.Entries.Symbolic_Link
                         | Tarlib.Entries.Character_Device
                         | Tarlib.Entries.Block_Device
                         | Tarlib.Entries.FIFO
                         | Tarlib.Entries.Volume_Label
        and then Size_Value /= 0
      then
         Result := (Code => Tarlib.Errors.Invalid_Size);
         return;
      end if;

      Parsed.Link_Length :=
        Tarlib.Internal.Fields.Text_Length (Header (158 .. 257));
      if Parsed.Kind in Tarlib.Entries.Hard_Link
                      | Tarlib.Entries.Symbolic_Link
      then
         if Parsed.Link_Length > 0 then
            Copy_Text (Header, 158, Parsed.Link_Length, Parsed.Link_Text, Cursor);
            Cursor := 0;
         end if;
      elsif Parsed.Link_Length > 0 then
         Result := (Code => Tarlib.Errors.Invalid_Metadata);
         return;
      end if;

      if Is_USTAR then
         Tarlib.Internal.Fields.Get_Numeric
           (Header (330 .. 337), Major_Value, Result);
         if Result.Code /= Tarlib.Errors.Success then
            return;
         elsif Major_Value
           > Interfaces.Unsigned_64 (Tarlib.Entries.Device_Number'Last)
         then
            Result := (Code => Tarlib.Errors.Invalid_Metadata);
            return;
         end if;

         Tarlib.Internal.Fields.Get_Numeric
           (Header (338 .. 345), Minor_Value, Result);
         if Result.Code /= Tarlib.Errors.Success then
            return;
         elsif Minor_Value
           > Interfaces.Unsigned_64 (Tarlib.Entries.Device_Number'Last)
         then
            Result := (Code => Tarlib.Errors.Invalid_Metadata);
            return;
         end if;

         if Parsed.Kind in Tarlib.Entries.Character_Device
                          | Tarlib.Entries.Block_Device
         then
            Parsed.Device :=
              (Major => Tarlib.Entries.Device_Number (Major_Value),
               Minor => Tarlib.Entries.Device_Number (Minor_Value));
         elsif Major_Value /= 0 or else Minor_Value /= 0 then
            Result := (Code => Tarlib.Errors.Invalid_Metadata);
            return;
         end if;
      end if;

      if Is_Old_GNU and then Parsed.Kind = Tarlib.Entries.Multi_Volume then
         Tarlib.Internal.Fields.Get_Numeric
           (Header (370 .. 381), Offset_Value, Result);
         if Result.Code /= Tarlib.Errors.Success then
            return;
         end if;
         Parsed.Multi_Volume_Offset :=
           Tarlib.Entries.Archive_Offset (Offset_Value);
         Parsed.Has_Multi_Volume_Offset := True;
      end if;

      if Is_POSIX_USTAR and then Prefix_Length > 0 then
         Copy_Text (Header, 346, Prefix_Length, Parsed.Path_Text, Cursor);
         Cursor := Cursor + 1;
         Parsed.Path_Text (Cursor) := '/';
      end if;
      Copy_Text (Header, 1, Name_Length, Parsed.Path_Text, Cursor);

      Parsed.Path_Length := Cursor;
      if Tarlib.Internal.Paths.Split
           (Parsed.Path_Text (1 .. Parsed.Path_Length)).Status.Code
         /= Tarlib.Errors.Success
      then
         Result := (Code => Tarlib.Errors.Invalid_Path);
         return;
      end if;

      if Is_Legacy
        and then Parsed.Kind = Tarlib.Entries.Regular_File
        and then Parsed.Path_Text (Parsed.Path_Length) = '/'
      then
         if Size_Value /= 0 then
            Result := (Code => Tarlib.Errors.Invalid_Size);
            return;
         end if;

         Parsed.Kind := Tarlib.Entries.Directory;
      end if;

      if Is_Old_GNU and then Parsed.Kind = Tarlib.Entries.GNU_Sparse then
         Parse_Old_GNU_Sparse (Header, Parsed, Result);
         if Result.Code /= Tarlib.Errors.Success then
            return;
         end if;
      end if;

      Parsed.Size := Tarlib.Byte_Count (Size_Value);
      Parsed.Metadata :=
        (Mode  => Tarlib.Entries.File_Mode (Mode_Value),
         UID   => Tarlib.Entries.Owner_Id (UID_Value),
         GID   => Tarlib.Entries.Owner_Id (GID_Value),
         MTime => Tarlib.Entries.Timestamp (MTime_Value),
         ATime => Tarlib.Entries.Default_Timestamp,
         CTime => Tarlib.Entries.Default_Timestamp,
         User_Name => <>,
         Group_Name => <>);
      Cursor := 0;
      if User_Length > 0 then
         Parsed.Metadata.User_Name.Length := User_Length;
         Copy_Text
           (Header, 266, User_Length, Parsed.Metadata.User_Name.Data, Cursor);
         Cursor := 0;
      end if;
      if Group_Length > 0 then
         Parsed.Metadata.Group_Name.Length := Group_Length;
         Copy_Text
           (Header, 298, Group_Length, Parsed.Metadata.Group_Name.Data, Cursor);
      end if;
      Result := Tarlib.Errors.OK;
   end Parse;
end Tarlib.Internal.Headers;
