with Interfaces;
with Tarlib.Internal.Constants;
with Tarlib.Internal.Fields;
with Tarlib.Internal.Headers;
with Tarlib.Internal.Padding;
with Tarlib.Internal.Paths;

package body Tarlib.Readers is
   use type Ada.Streams.Stream_Element_Offset;
   use type Ada.Streams.Stream_Element;
   use type Interfaces.Integer_64;
   use type Interfaces.Unsigned_64;
   use type Tarlib.Entries.Entry_Kind;
   use type Tarlib.Errors.Status_Code;

   procedure Mark_Input_Failure
     (Archive : in out Reader;
      Result  : Tarlib.Errors.Status) is
   begin
      if Result.Code /= Tarlib.Errors.Success then
         Archive.Current_State := Failed;
      end if;
   end Mark_Input_Failure;

   procedure Clear_Pending_Extension (Archive : in out Reader) is
   begin
      Archive.Pending_Path_Length := 0;
      Archive.Pending_Link_Path_Length := 0;
      Archive.Has_Pending_Size := False;
      Archive.Has_Pending_MTime := False;
      Archive.Has_Pending_ATime := False;
      Archive.Has_Pending_CTime := False;
      Archive.Has_Pending_UID := False;
      Archive.Has_Pending_GID := False;
      Archive.Has_Pending_User_Name := False;
      Archive.Has_Pending_Group_Name := False;
      Archive.Pending_Extension_Count := 0;
      Archive.Has_Pending_Device_Major := False;
      Archive.Has_Pending_Device_Minor := False;
      Archive.Pending_Sparse_Count := 0;
      Archive.Pending_Sparse_Size := 0;
      Archive.Has_Pending_Sparse_Size := False;
      Archive.Has_Pending_Sparse_Map := False;
      Archive.Pending_Sparse_Offset := 0;
      Archive.Has_Pending_Sparse_Offset := False;
      Archive.Pending_Volume_Offset := 0;
      Archive.Has_Pending_Volume_Offset := False;
      Archive.Pending_XAttr_Count := 0;
      Archive.Has_Pending_ACL_Access := False;
      Archive.Has_Pending_ACL_Default := False;
      Archive.Has_Pending_File_Flags := False;
      Archive.Has_Pending_Extension := False;
   end Clear_Pending_Extension;

   procedure Read_Exact
     (Archive : in out Reader;
      Data    : out Ada.Streams.Stream_Element_Array;
      Result  : out Tarlib.Errors.Status)
   is
      First_Unread : Ada.Streams.Stream_Element_Offset := Data'First;
      Last         : Ada.Streams.Stream_Element_Offset;
   begin
      while First_Unread <= Data'Last loop
         Archive.Source.Read (Data (First_Unread .. Data'Last), Last, Result);
         Mark_Input_Failure (Archive, Result);
         if Result.Code /= Tarlib.Errors.Success then
            return;
         elsif Last < First_Unread then
            Result := (Code => Tarlib.Errors.Invalid_Archive);
            Archive.Current_State := Failed;
            return;
         end if;

         First_Unread := Last + 1;
      end loop;

      Result := Tarlib.Errors.OK;
   end Read_Exact;

   procedure Discard
     (Archive : in out Reader;
      Count   : Interfaces.Unsigned_64;
      Result  : out Tarlib.Errors.Status)
   is
      Buffer    : Ada.Streams.Stream_Element_Array (1 .. 512);
      Remaining : Interfaces.Unsigned_64 := Count;
      Chunk     : Ada.Streams.Stream_Element_Offset;
   begin
      while Remaining > 0 loop
         Chunk :=
           Ada.Streams.Stream_Element_Offset
             (Interfaces.Unsigned_64'Min
                (Remaining, Interfaces.Unsigned_64 (Buffer'Length)));
         Read_Exact (Archive, Buffer (1 .. Chunk), Result);
         if Result.Code /= Tarlib.Errors.Success then
            return;
         end if;
         Remaining := Remaining - Interfaces.Unsigned_64 (Chunk);
      end loop;

      Result := Tarlib.Errors.OK;
   end Discard;

   procedure Complete_Active_Entry
     (Archive : in out Reader;
      Result  : out Tarlib.Errors.Status) is
   begin
      Discard (Archive, Archive.Active_Physical_Size, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Discard (Archive, Interfaces.Unsigned_64 (Archive.Remaining_Padding), Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Archive.Remaining_Size := 0;
      Archive.Active_Physical_Size := 0;
      Archive.Remaining_Padding := 0;
      Archive.Active_Logical_Offset := 0;
      Archive.Active_Sparse_Count := 0;
      Archive.Active_Sparse_Index := 1;
      Archive.Current_State := Ready;
      Result := Tarlib.Errors.OK;
   end Complete_Active_Entry;

   procedure Set_Pending_Path
     (Archive : in out Reader;
      Data    : Ada.Streams.Stream_Element_Array;
      First   : Ada.Streams.Stream_Element_Offset;
      Last    : Ada.Streams.Stream_Element_Offset;
      Result  : out Tarlib.Errors.Status)
   is
      Length : Natural;
      Split  : Tarlib.Internal.Paths.Path_Split;
   begin
      if Last < First then
         Result := (Code => Tarlib.Errors.Invalid_Archive);
         Archive.Current_State := Failed;
         return;
      end if;

      Length := Natural (Last - First + 1);
      if Length = 0 then
         Result := (Code => Tarlib.Errors.Invalid_Archive);
         Archive.Current_State := Failed;
         return;
      elsif Length > Max_Path_Length then
         Result := (Code => Tarlib.Errors.Path_Too_Long);
         Archive.Current_State := Failed;
         return;
      end if;

      for Offset in 0 .. Length - 1 loop
         Archive.Pending_Path (Offset + 1) :=
           Character'Val
             (Data (First + Ada.Streams.Stream_Element_Offset (Offset)));
      end loop;

      Split := Tarlib.Internal.Paths.Split (Archive.Pending_Path (1 .. Length));
      if Split.Status.Code not in Tarlib.Errors.Success | Tarlib.Errors.Path_Too_Long then
         Result := Split.Status;
         Archive.Current_State := Failed;
         return;
      end if;

      Archive.Pending_Path_Length := Length;
      Result := Tarlib.Errors.OK;
   end Set_Pending_Path;

   procedure Set_Pending_Link_Path
     (Archive : in out Reader;
      Data    : Ada.Streams.Stream_Element_Array;
      First   : Ada.Streams.Stream_Element_Offset;
      Last    : Ada.Streams.Stream_Element_Offset;
      Result  : out Tarlib.Errors.Status)
   is
      Length : Natural;
   begin
      if Last < First then
         Result := (Code => Tarlib.Errors.Invalid_Archive);
         Archive.Current_State := Failed;
         return;
      end if;

      Length := Natural (Last - First + 1);
      if Length = 0 then
         Result := (Code => Tarlib.Errors.Invalid_Archive);
         Archive.Current_State := Failed;
         return;
      elsif Length > Max_Path_Length then
         Result := (Code => Tarlib.Errors.Path_Too_Long);
         Archive.Current_State := Failed;
         return;
      end if;

      for Offset in 0 .. Length - 1 loop
         if Data (First + Ada.Streams.Stream_Element_Offset (Offset)) = 0 then
            Result := (Code => Tarlib.Errors.Invalid_Archive);
            Archive.Current_State := Failed;
            return;
         end if;

         Archive.Pending_Link_Path (Offset + 1) :=
           Character'Val
             (Data (First + Ada.Streams.Stream_Element_Offset (Offset)));
      end loop;

      Archive.Pending_Link_Path_Length := Length;
      Result := Tarlib.Errors.OK;
   end Set_Pending_Link_Path;

   procedure Set_Metadata_Text_From_Data
     (Archive : in out Reader;
      Target  : in out Tarlib.Entries.Metadata_Text;
      Data    : Ada.Streams.Stream_Element_Array;
      First   : Ada.Streams.Stream_Element_Offset;
      Last    : Ada.Streams.Stream_Element_Offset;
      Result  : out Tarlib.Errors.Status)
   is
      Length : Natural := 0;
      Text   : String (1 .. Tarlib.Entries.Max_Metadata_Text_Length);
   begin
      if Last >= First then
         Length := Natural (Last - First + 1);
      end if;

      if Length > Tarlib.Entries.Max_Metadata_Text_Length then
         Result := (Code => Tarlib.Errors.Invalid_Metadata);
         Archive.Current_State := Failed;
         return;
      end if;

      for Offset in 0 .. Length - 1 loop
         Text (Offset + 1) :=
           Character'Val
             (Data (First + Ada.Streams.Stream_Element_Offset (Offset)));
      end loop;

      Tarlib.Entries.Set_Text (Target, Text (1 .. Length), Result);
      if Result.Code /= Tarlib.Errors.Success then
         Archive.Current_State := Failed;
      end if;
   end Set_Metadata_Text_From_Data;

   procedure Set_Pending_Text
     (Archive : in out Reader;
      Data    : Ada.Streams.Stream_Element_Array;
      First   : Ada.Streams.Stream_Element_Offset;
      Last    : Ada.Streams.Stream_Element_Offset;
      Field   : String;
      Global  : Boolean;
      Result  : out Tarlib.Errors.Status) is
   begin
      if Field = "uname" then
         if Global then
            Set_Metadata_Text_From_Data
              (Archive, Archive.Global_User_Name, Data, First, Last, Result);
            if Result.Code = Tarlib.Errors.Success then
               Archive.Has_Global_User_Name := Last >= First;
            end if;
         else
            Set_Metadata_Text_From_Data
              (Archive, Archive.Pending_User_Name, Data, First, Last, Result);
            if Result.Code = Tarlib.Errors.Success then
               Archive.Has_Pending_User_Name := True;
            end if;
         end if;
      elsif Field = "gname" then
         if Global then
            Set_Metadata_Text_From_Data
              (Archive, Archive.Global_Group_Name, Data, First, Last, Result);
            if Result.Code = Tarlib.Errors.Success then
               Archive.Has_Global_Group_Name := Last >= First;
            end if;
         else
            Set_Metadata_Text_From_Data
              (Archive, Archive.Pending_Group_Name, Data, First, Last, Result);
            if Result.Code = Tarlib.Errors.Success then
               Archive.Has_Pending_Group_Name := True;
            end if;
         end if;
      else
         Result := Tarlib.Errors.OK;
      end if;
   end Set_Pending_Text;

   procedure Set_Pending_Extension_Record
     (Archive     : in out Reader;
      Data        : Ada.Streams.Stream_Element_Array;
      Key_First   : Ada.Streams.Stream_Element_Offset;
      Key_Last    : Ada.Streams.Stream_Element_Offset;
      Value_First : Ada.Streams.Stream_Element_Offset;
      Value_Last  : Ada.Streams.Stream_Element_Offset;
      Global      : Boolean;
      Result      : out Tarlib.Errors.Status)
   is
      Slot : Natural;
   begin
      if Global then
         Result := Tarlib.Errors.OK;
         return;
      elsif Archive.Pending_Extension_Count = Max_Extended_Records then
         Result := (Code => Tarlib.Errors.Invalid_Metadata);
         Archive.Current_State := Failed;
         return;
      end if;

      Slot := Archive.Pending_Extension_Count + 1;
      Set_Metadata_Text_From_Data
        (Archive, Archive.Pending_Extension_Keys (Slot), Data, Key_First,
         Key_Last, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Set_Metadata_Text_From_Data
        (Archive, Archive.Pending_Extension_Values (Slot), Data, Value_First,
         Value_Last, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Archive.Pending_Extension_Count := Slot;
      Result := Tarlib.Errors.OK;
   end Set_Pending_Extension_Record;

   procedure Parse_Unsigned
     (Archive : in out Reader;
      Data    : Ada.Streams.Stream_Element_Array;
      First   : Ada.Streams.Stream_Element_Offset;
      Last    : Ada.Streams.Stream_Element_Offset;
      Value   : out Interfaces.Unsigned_64;
      Result  : out Tarlib.Errors.Status)
   is
      Digit : Interfaces.Unsigned_64;
      Index : Ada.Streams.Stream_Element_Offset := First;
      Saw_Digit : Boolean := False;
   begin
      Value := 0;
      if Last < First then
         Result := (Code => Tarlib.Errors.Invalid_Archive);
         Archive.Current_State := Failed;
         return;
      end if;

      if Data (Index) = Character'Pos ('+') then
         Index := Index + 1;
      end if;

      while Index <= Last loop
         if Data (Index) not in Character'Pos ('0') .. Character'Pos ('9') then
            Result := (Code => Tarlib.Errors.Invalid_Archive);
            Archive.Current_State := Failed;
            return;
         end if;

         Saw_Digit := True;
         Digit :=
           Interfaces.Unsigned_64
             (Ada.Streams.Stream_Element'Pos (Data (Index))
              - Character'Pos ('0'));
         if Value > (Interfaces.Unsigned_64'Last - Digit) / 10 then
            Result := (Code => Tarlib.Errors.Invalid_Archive);
            Archive.Current_State := Failed;
            return;
         end if;

         Value := Value * 10 + Digit;
         Index := Index + 1;
      end loop;

      if not Saw_Digit then
         Result := (Code => Tarlib.Errors.Invalid_Archive);
         Archive.Current_State := Failed;
         return;
      end if;

      Result := Tarlib.Errors.OK;
   end Parse_Unsigned;

   procedure Parse_Timestamp
     (Archive : in out Reader;
      Data    : Ada.Streams.Stream_Element_Array;
      First   : Ada.Streams.Stream_Element_Offset;
      Last    : Ada.Streams.Stream_Element_Offset;
      Value   : out Interfaces.Integer_64;
      Result  : out Tarlib.Errors.Status)
   is
      Digit        : Interfaces.Unsigned_64;
      Index        : Ada.Streams.Stream_Element_Offset := First;
      Magnitude    : Interfaces.Unsigned_64 := 0;
      Negative     : Boolean := False;
      Saw_Decimal  : Boolean := False;
      Whole_Digit_Count : Natural := 0;
      Fraction_Digit_Count : Natural := 0;
   begin
      Value := 0;
      if Last < First then
         Result := (Code => Tarlib.Errors.Invalid_Archive);
         Archive.Current_State := Failed;
         return;
      end if;

      if Data (Index) = Character'Pos ('+') then
         Index := Index + 1;
      elsif Data (Index) = Character'Pos ('-') then
         Negative := True;
         Index := Index + 1;
      end if;

      while Index <= Last loop
         if Data (Index) in Character'Pos ('0') .. Character'Pos ('9') then
            Digit :=
                Interfaces.Unsigned_64
                  (Ada.Streams.Stream_Element'Pos (Data (Index))
                   - Character'Pos ('0'));
            if Magnitude > (Interfaces.Unsigned_64'Last - Digit) / 10 then
               Result := (Code => Tarlib.Errors.Invalid_Archive);
               Archive.Current_State := Failed;
               return;
            end if;

            Magnitude := Magnitude * 10 + Digit;
            Whole_Digit_Count := Whole_Digit_Count + 1;
            Index := Index + 1;
         elsif Data (Index) = Character'Pos ('.') then
            Saw_Decimal := True;
            Index := Index + 1;
            exit;
         else
            Result := (Code => Tarlib.Errors.Invalid_Archive);
            Archive.Current_State := Failed;
            return;
         end if;
      end loop;

      if Whole_Digit_Count = 0 then
         Result := (Code => Tarlib.Errors.Invalid_Archive);
         Archive.Current_State := Failed;
         return;
      end if;

      if Saw_Decimal then
         while Index <= Last loop
            if Data (Index) not in Character'Pos ('0') .. Character'Pos ('9') then
               Result := (Code => Tarlib.Errors.Invalid_Archive);
               Archive.Current_State := Failed;
               return;
            end if;
            Fraction_Digit_Count := Fraction_Digit_Count + 1;
            Index := Index + 1;
         end loop;

         if Fraction_Digit_Count = 0 then
            Result := (Code => Tarlib.Errors.Invalid_Archive);
            Archive.Current_State := Failed;
            return;
         end if;
      end if;

      if Negative then
         if Magnitude
           > Interfaces.Unsigned_64 (Interfaces.Integer_64'Last) + 1
         then
            Result := (Code => Tarlib.Errors.Invalid_Archive);
            Archive.Current_State := Failed;
            return;
         elsif Magnitude = Interfaces.Unsigned_64 (Interfaces.Integer_64'Last) + 1
         then
            Value := Interfaces.Integer_64'First;
         else
            Value := -Interfaces.Integer_64 (Magnitude);
         end if;
      else
         if Magnitude > Interfaces.Unsigned_64 (Interfaces.Integer_64'Last) then
            Result := (Code => Tarlib.Errors.Invalid_Archive);
            Archive.Current_State := Failed;
            return;
         end if;
         Value := Interfaces.Integer_64 (Magnitude);
      end if;

      Result := Tarlib.Errors.OK;
   end Parse_Timestamp;

   procedure Set_Pending_Numeric
     (Archive : in out Reader;
      Data    : Ada.Streams.Stream_Element_Array;
      First   : Ada.Streams.Stream_Element_Offset;
      Last    : Ada.Streams.Stream_Element_Offset;
      Field   : String;
      Global  : Boolean;
      Result  : out Tarlib.Errors.Status)
   is
      Value : Interfaces.Unsigned_64;
      Time_Value : Interfaces.Integer_64;
   begin
      if Last < First and then Global then
         if Field = "mtime" then
            Archive.Has_Global_MTime := False;
         elsif Field = "atime" then
            Archive.Has_Global_ATime := False;
         elsif Field = "ctime" then
            Archive.Has_Global_CTime := False;
         elsif Field = "uid" then
            Archive.Has_Global_UID := False;
         elsif Field = "gid" then
            Archive.Has_Global_GID := False;
         end if;

         Result := Tarlib.Errors.OK;
         return;
      end if;

      if Global
        and then (Field = "size"
                  or else Field = "devmajor"
                  or else Field = "devminor")
      then
         Result := Tarlib.Errors.OK;
         return;
      end if;

      if Field = "mtime" or else Field = "atime" or else Field = "ctime" then
         Parse_Timestamp (Archive, Data, First, Last, Time_Value, Result);
      else
         Parse_Unsigned (Archive, Data, First, Last, Value, Result);
      end if;
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      if Field = "size" then
         if Global then
            Result := Tarlib.Errors.OK;
            return;
         else
            Archive.Pending_Size := Tarlib.Byte_Count (Value);
            Archive.Has_Pending_Size := True;
         end if;
      elsif Field = "mtime" then
         if Global then
            Archive.Global_MTime := Tarlib.Entries.Timestamp (Time_Value);
            Archive.Has_Global_MTime := True;
         else
            Archive.Pending_MTime := Tarlib.Entries.Timestamp (Time_Value);
            Archive.Has_Pending_MTime := True;
         end if;
      elsif Field = "atime" then
         if Global then
            Archive.Global_ATime := Tarlib.Entries.Timestamp (Time_Value);
            Archive.Has_Global_ATime := True;
         else
            Archive.Pending_ATime := Tarlib.Entries.Timestamp (Time_Value);
            Archive.Has_Pending_ATime := True;
         end if;
      elsif Field = "ctime" then
         if Global then
            Archive.Global_CTime := Tarlib.Entries.Timestamp (Time_Value);
            Archive.Has_Global_CTime := True;
         else
            Archive.Pending_CTime := Tarlib.Entries.Timestamp (Time_Value);
            Archive.Has_Pending_CTime := True;
         end if;
      elsif Field = "uid" then
         if Global then
            Archive.Global_UID := Tarlib.Entries.Owner_Id (Value);
            Archive.Has_Global_UID := True;
         else
            Archive.Pending_UID := Tarlib.Entries.Owner_Id (Value);
            Archive.Has_Pending_UID := True;
         end if;
      elsif Field = "gid" then
         if Global then
            Archive.Global_GID := Tarlib.Entries.Owner_Id (Value);
            Archive.Has_Global_GID := True;
         else
            Archive.Pending_GID := Tarlib.Entries.Owner_Id (Value);
            Archive.Has_Pending_GID := True;
         end if;
      elsif Field = "devmajor" then
         if not Global then
            if Value
              > Interfaces.Unsigned_64 (Tarlib.Entries.Device_Number'Last)
            then
               Result := (Code => Tarlib.Errors.Invalid_Metadata);
               Archive.Current_State := Failed;
               return;
            end if;

            Archive.Pending_Device_Major :=
              Tarlib.Entries.Device_Number (Value);
            Archive.Has_Pending_Device_Major := True;
         end if;
      elsif Field = "devminor" then
         if not Global then
            if Value
              > Interfaces.Unsigned_64 (Tarlib.Entries.Device_Number'Last)
            then
               Result := (Code => Tarlib.Errors.Invalid_Metadata);
               Archive.Current_State := Failed;
               return;
            end if;

            Archive.Pending_Device_Minor :=
              Tarlib.Entries.Device_Number (Value);
            Archive.Has_Pending_Device_Minor := True;
         end if;
      end if;

      Result := Tarlib.Errors.OK;
   end Set_Pending_Numeric;

   procedure Set_Pending_Sparse_Size
     (Archive : in out Reader;
      Data    : Ada.Streams.Stream_Element_Array;
      First   : Ada.Streams.Stream_Element_Offset;
      Last    : Ada.Streams.Stream_Element_Offset;
      Result  : out Tarlib.Errors.Status)
   is
      Value : Interfaces.Unsigned_64;
   begin
      Parse_Unsigned (Archive, Data, First, Last, Value, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Archive.Pending_Sparse_Size := Tarlib.Byte_Count (Value);
      Archive.Has_Pending_Sparse_Size := True;
      Result := Tarlib.Errors.OK;
   end Set_Pending_Sparse_Size;

   procedure Set_Pending_Volume_Offset
     (Archive : in out Reader;
      Data    : Ada.Streams.Stream_Element_Array;
      First   : Ada.Streams.Stream_Element_Offset;
      Last    : Ada.Streams.Stream_Element_Offset;
      Result  : out Tarlib.Errors.Status)
   is
      Value : Interfaces.Unsigned_64;
   begin
      Parse_Unsigned (Archive, Data, First, Last, Value, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Archive.Pending_Volume_Offset := Tarlib.Entries.Archive_Offset (Value);
      Archive.Has_Pending_Volume_Offset := True;
      Result := Tarlib.Errors.OK;
   end Set_Pending_Volume_Offset;

   procedure Set_Pending_Sparse_Map
     (Archive : in out Reader;
      Data    : Ada.Streams.Stream_Element_Array;
      First   : Ada.Streams.Stream_Element_Offset;
      Last    : Ada.Streams.Stream_Element_Offset;
      Result  : out Tarlib.Errors.Status)
   is
      Index        : Ada.Streams.Stream_Element_Offset := First;
      Value        : Interfaces.Unsigned_64 := 0;
      Digit        : Interfaces.Unsigned_64;
      Saw_Digit    : Boolean := False;
      Need_Offset  : Boolean := True;
      Slot         : Natural := 0;
      Last_End     : Tarlib.Byte_Count := 0;
   begin
      if Last < First then
         Result := (Code => Tarlib.Errors.Invalid_Archive);
         Archive.Current_State := Failed;
         return;
      end if;

      Archive.Pending_Sparse_Count := 0;
      while Index <= Last + 1 loop
         if Index <= Last
           and then Data (Index) in Character'Pos ('0') .. Character'Pos ('9')
         then
            Digit :=
              Interfaces.Unsigned_64
                (Ada.Streams.Stream_Element'Pos (Data (Index))
                 - Character'Pos ('0'));
            if Value > (Interfaces.Unsigned_64'Last - Digit) / 10 then
               Result := (Code => Tarlib.Errors.Invalid_Archive);
               Archive.Current_State := Failed;
               return;
            end if;

            Value := Value * 10 + Digit;
            Saw_Digit := True;
            Index := Index + 1;
         elsif Index > Last or else Data (Index) = Character'Pos (',') then
            if not Saw_Digit then
               Result := (Code => Tarlib.Errors.Invalid_Archive);
               Archive.Current_State := Failed;
               return;
            end if;

            if Need_Offset then
               if Slot = Max_Sparse_Extents then
                  Result := (Code => Tarlib.Errors.Invalid_Metadata);
                  Archive.Current_State := Failed;
                  return;
               end if;

               Slot := Slot + 1;
               Archive.Pending_Sparse_Extents (Slot).Offset :=
                 Tarlib.Byte_Count (Value);
               Need_Offset := False;
            else
               declare
                  Offset : constant Tarlib.Byte_Count :=
                    Archive.Pending_Sparse_Extents (Slot).Offset;
                  Length : constant Tarlib.Byte_Count :=
                    Tarlib.Byte_Count (Value);
               begin
                  if Offset < Last_End
                    or else Length
                      > Tarlib.Byte_Count'Last - Offset
                  then
                     Result := (Code => Tarlib.Errors.Invalid_Metadata);
                     Archive.Current_State := Failed;
                     return;
                  end if;

                  Archive.Pending_Sparse_Extents (Slot).Length := Length;
                  Last_End := Offset + Length;
               end;
               Need_Offset := True;
            end if;

            Value := 0;
            Saw_Digit := False;
            Index := Index + 1;
         else
            Result := (Code => Tarlib.Errors.Invalid_Archive);
            Archive.Current_State := Failed;
            return;
         end if;
      end loop;

      if not Need_Offset or else Slot = 0 then
         Result := (Code => Tarlib.Errors.Invalid_Archive);
         Archive.Current_State := Failed;
         return;
      end if;

      Archive.Pending_Sparse_Count := Slot;
      Archive.Has_Pending_Sparse_Map := True;
      Result := Tarlib.Errors.OK;
   end Set_Pending_Sparse_Map;

   procedure Append_Pending_Sparse_Extent
     (Archive : in out Reader;
      Offset  : Tarlib.Byte_Count;
      Length  : Tarlib.Byte_Count;
      Result  : out Tarlib.Errors.Status);

   procedure Set_Pending_Sparse_Offset
     (Archive : in out Reader;
      Data    : Ada.Streams.Stream_Element_Array;
      First   : Ada.Streams.Stream_Element_Offset;
      Last    : Ada.Streams.Stream_Element_Offset;
      Result  : out Tarlib.Errors.Status)
   is
      Value : Interfaces.Unsigned_64;
   begin
      Parse_Unsigned (Archive, Data, First, Last, Value, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Archive.Pending_Sparse_Offset := Tarlib.Byte_Count (Value);
      Archive.Has_Pending_Sparse_Offset := True;
      Result := Tarlib.Errors.OK;
   end Set_Pending_Sparse_Offset;

   procedure Set_Pending_Sparse_Length
     (Archive : in out Reader;
      Data    : Ada.Streams.Stream_Element_Array;
      First   : Ada.Streams.Stream_Element_Offset;
      Last    : Ada.Streams.Stream_Element_Offset;
      Result  : out Tarlib.Errors.Status)
   is
      Value : Interfaces.Unsigned_64;
   begin
      Parse_Unsigned (Archive, Data, First, Last, Value, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      elsif not Archive.Has_Pending_Sparse_Offset then
         Result := (Code => Tarlib.Errors.Invalid_Metadata);
         Archive.Current_State := Failed;
         return;
      end if;

      Append_Pending_Sparse_Extent
        (Archive, Archive.Pending_Sparse_Offset, Tarlib.Byte_Count (Value),
         Result);
      if Result.Code = Tarlib.Errors.Success then
         Archive.Pending_Sparse_Offset := 0;
         Archive.Has_Pending_Sparse_Offset := False;
      end if;
   end Set_Pending_Sparse_Length;

   procedure Append_Pending_Sparse_Extent
     (Archive : in out Reader;
      Offset  : Tarlib.Byte_Count;
      Length  : Tarlib.Byte_Count;
      Result  : out Tarlib.Errors.Status)
   is
      Previous_End : Tarlib.Byte_Count := 0;
   begin
      if Archive.Pending_Sparse_Count = Max_Sparse_Extents
        or else Length > Tarlib.Byte_Count'Last - Offset
      then
         Result := (Code => Tarlib.Errors.Invalid_Metadata);
         Archive.Current_State := Failed;
         return;
      end if;

      if Archive.Pending_Sparse_Count > 0 then
         declare
            Previous : constant Sparse_Extent :=
              Archive.Pending_Sparse_Extents (Archive.Pending_Sparse_Count);
         begin
            Previous_End := Previous.Offset + Previous.Length;
         end;
      end if;

      if Offset < Previous_End then
         Result := (Code => Tarlib.Errors.Invalid_Metadata);
         Archive.Current_State := Failed;
         return;
      end if;

      Archive.Pending_Sparse_Count := Archive.Pending_Sparse_Count + 1;
      Archive.Pending_Sparse_Extents (Archive.Pending_Sparse_Count) :=
        (Offset => Offset, Length => Length);
      Archive.Has_Pending_Sparse_Map := True;
      Result := Tarlib.Errors.OK;
   end Append_Pending_Sparse_Extent;

   procedure Set_Pending_Vendor_Text
     (Archive : in out Reader;
      Data    : Ada.Streams.Stream_Element_Array;
      First   : Ada.Streams.Stream_Element_Offset;
      Last    : Ada.Streams.Stream_Element_Offset;
      Target  : in out Vendor_Text;
      Flag    : in out Boolean;
      Result  : out Tarlib.Errors.Status)
   is
   begin
      Set_Metadata_Text_From_Data (Archive, Target, Data, First, Last, Result);
      if Result.Code = Tarlib.Errors.Success then
         Flag := Last >= First;
      end if;
   end Set_Pending_Vendor_Text;

   procedure Add_Pending_XAttr
     (Archive     : in out Reader;
      Data        : Ada.Streams.Stream_Element_Array;
      Key_First   : Ada.Streams.Stream_Element_Offset;
      Key_Last    : Ada.Streams.Stream_Element_Offset;
      Value_First : Ada.Streams.Stream_Element_Offset;
      Value_Last  : Ada.Streams.Stream_Element_Offset;
      Result      : out Tarlib.Errors.Status)
   is
      Prefix : constant String := "SCHILY.xattr.";
      Prefix_Length : constant Ada.Streams.Stream_Element_Offset :=
        Ada.Streams.Stream_Element_Offset (Prefix'Length);
      Slot : Natural;
   begin
      if Key_Last - Key_First + 1 <= Prefix_Length
        or else Archive.Pending_XAttr_Count = Max_Vendor_Records
      then
         Result := (Code => Tarlib.Errors.Invalid_Metadata);
         Archive.Current_State := Failed;
         return;
      end if;

      Slot := Archive.Pending_XAttr_Count + 1;
      Set_Metadata_Text_From_Data
        (Archive, Archive.Pending_XAttr_Names (Slot), Data,
         Key_First + Prefix_Length, Key_Last, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Set_Metadata_Text_From_Data
        (Archive, Archive.Pending_XAttr_Values (Slot), Data,
         Value_First, Value_Last, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Archive.Pending_XAttr_Count := Slot;
      Result := Tarlib.Errors.OK;
   end Add_Pending_XAttr;

   procedure Read_Old_GNU_Sparse_Extensions
     (Archive : in out Reader;
      Result  : out Tarlib.Errors.Status)
   is
      Header       : Tarlib.Internal.Constants.Header_Block;
      Offset_Value : Interfaces.Unsigned_64;
      Length_Value : Interfaces.Unsigned_64;
      First        : Ada.Streams.Stream_Element_Offset;
      More         : Boolean := True;
   begin
      while More loop
         Read_Exact (Archive, Header, Result);
         if Result.Code /= Tarlib.Errors.Success then
            return;
         end if;

         First := 1;
         for Slot in 1 .. 21 loop
            exit when First + 23 > 504;
            if Header (First) /= 0 then
               Tarlib.Internal.Fields.Get_Numeric
                 (Header (First .. First + 11), Offset_Value, Result);
               if Result.Code /= Tarlib.Errors.Success then
                  Archive.Current_State := Failed;
                  return;
               end if;

               Tarlib.Internal.Fields.Get_Numeric
                 (Header (First + 12 .. First + 23), Length_Value, Result);
               if Result.Code /= Tarlib.Errors.Success then
                  Archive.Current_State := Failed;
                  return;
               end if;

               Append_Pending_Sparse_Extent
                 (Archive, Tarlib.Byte_Count (Offset_Value),
                  Tarlib.Byte_Count (Length_Value), Result);
               if Result.Code /= Tarlib.Errors.Success then
                  return;
               end if;
            end if;

            First := First + 24;
         end loop;

         More := Header (505) /= 0;
      end loop;

      Result := Tarlib.Errors.OK;
   end Read_Old_GNU_Sparse_Extensions;

   function Key_Has_Prefix
     (Data   : Ada.Streams.Stream_Element_Array;
      First  : Ada.Streams.Stream_Element_Offset;
      Last   : Ada.Streams.Stream_Element_Offset;
      Prefix : String) return Boolean
   is
   begin
      if Last - First + 1 < Ada.Streams.Stream_Element_Offset (Prefix'Length) then
         return False;
      end if;

      for Offset in 0 .. Prefix'Length - 1 loop
         if Data (First + Ada.Streams.Stream_Element_Offset (Offset))
           /= Ada.Streams.Stream_Element
                (Character'Pos (Prefix (Prefix'First + Offset)))
         then
            return False;
         end if;
      end loop;

      return True;
   end Key_Has_Prefix;

   function Key_Equals
     (Data   : Ada.Streams.Stream_Element_Array;
      First  : Ada.Streams.Stream_Element_Offset;
      Last   : Ada.Streams.Stream_Element_Offset;
      Key    : String) return Boolean
   is
   begin
      if Last - First + 1 /= Ada.Streams.Stream_Element_Offset (Key'Length) then
         return False;
      end if;

      for Offset in 0 .. Key'Length - 1 loop
         if Data (First + Ada.Streams.Stream_Element_Offset (Offset))
           /= Ada.Streams.Stream_Element
                (Character'Pos (Key (Key'First + Offset)))
         then
            return False;
         end if;
      end loop;

      return True;
   end Key_Equals;

   procedure Parse_PAX
     (Archive : in out Reader;
      Data    : Ada.Streams.Stream_Element_Array;
      Length  : Natural;
      Global  : Boolean;
      Result  : out Tarlib.Errors.Status)
   is
      Position : Ada.Streams.Stream_Element_Offset := Data'First;
      Last     : constant Ada.Streams.Stream_Element_Offset :=
        Data'First + Ada.Streams.Stream_Element_Offset (Length) - 1;
      Record_First  : Ada.Streams.Stream_Element_Offset;
      Record_Length : Natural;
      Record_End    : Ada.Streams.Stream_Element_Offset;
      Key_First     : Ada.Streams.Stream_Element_Offset;
      Equal_Index   : Ada.Streams.Stream_Element_Offset;
      Value_First   : Ada.Streams.Stream_Element_Offset;
      Value_Last    : Ada.Streams.Stream_Element_Offset;
      Digit         : Natural;
   begin
      while Position <= Last loop
         Record_First := Position;
         Record_Length := 0;
         while Position <= Last and then Data (Position) in Character'Pos ('0')
                                                     .. Character'Pos ('9')
         loop
            Digit :=
              Natural
                (Ada.Streams.Stream_Element'Pos (Data (Position))
                 - Character'Pos ('0'));
            if Record_Length > (Natural'Last - Digit) / 10 then
               Result := (Code => Tarlib.Errors.Invalid_Archive);
               Archive.Current_State := Failed;
               return;
            end if;

            Record_Length :=
              Record_Length * 10 + Digit;
            Position := Position + 1;
         end loop;

         if Position > Last or else Data (Position) /= Character'Pos (' ')
           or else Record_Length = 0
         then
            Result := (Code => Tarlib.Errors.Invalid_Archive);
            Archive.Current_State := Failed;
            return;
         end if;

         Record_End :=
           Record_First + Ada.Streams.Stream_Element_Offset (Record_Length) - 1;
         if Record_End > Last
           or else Data (Record_End) /= Character'Pos (Character'Val (10))
         then
            Result := (Code => Tarlib.Errors.Invalid_Archive);
            Archive.Current_State := Failed;
            return;
         end if;

         Key_First := Position + 1;
         Equal_Index := Key_First;
         while Equal_Index < Record_End
           and then Data (Equal_Index) /= Character'Pos ('=')
         loop
            Equal_Index := Equal_Index + 1;
         end loop;

         if Equal_Index = Key_First or else Equal_Index >= Record_End then
            Result := (Code => Tarlib.Errors.Invalid_Archive);
            Archive.Current_State := Failed;
            return;
         end if;

         Value_First := Equal_Index + 1;
         Value_Last := Record_End - 1;
         if Key_Equals (Data, Key_First, Equal_Index - 1, "GNU.sparse.map")
         then
            if Global then
               Result := Tarlib.Errors.OK;
            else
               Set_Pending_Sparse_Map
                 (Archive, Data, Value_First, Value_Last, Result);
               if Result.Code /= Tarlib.Errors.Success then
                  return;
               end if;
            end if;
         elsif Key_Equals (Data, Key_First, Equal_Index - 1, "GNU.sparse.size")
           or else Key_Equals
             (Data, Key_First, Equal_Index - 1, "GNU.sparse.realsize")
           or else Key_Equals
             (Data, Key_First, Equal_Index - 1, "SCHILY.realsize")
           or else Key_Equals
             (Data, Key_First, Equal_Index - 1, "LIBARCHIVE.sparse.size")
           or else Key_Equals
             (Data, Key_First, Equal_Index - 1, "LIBARCHIVE.sparse.realsize")
         then
            if Global then
               Result := Tarlib.Errors.OK;
            else
               Set_Pending_Sparse_Size
                 (Archive, Data, Value_First, Value_Last, Result);
               if Result.Code /= Tarlib.Errors.Success then
                  return;
               end if;
            end if;
         elsif Key_Equals (Data, Key_First, Equal_Index - 1, "SCHILY.offset")
           or else Key_Equals
             (Data, Key_First, Equal_Index - 1, "LIBARCHIVE.sparse.offset")
           or else Key_Equals
             (Data, Key_First, Equal_Index - 1, "GNU.sparse.offset")
         then
            if Global then
               Result := Tarlib.Errors.OK;
            else
               Set_Pending_Sparse_Offset
                 (Archive, Data, Value_First, Value_Last, Result);
               if Result.Code /= Tarlib.Errors.Success then
                  return;
               end if;
            end if;
         elsif Key_Equals (Data, Key_First, Equal_Index - 1, "SCHILY.numbytes")
           or else Key_Equals
             (Data, Key_First, Equal_Index - 1, "LIBARCHIVE.sparse.numbytes")
           or else Key_Equals
             (Data, Key_First, Equal_Index - 1, "GNU.sparse.numbytes")
         then
            if Global then
               Result := Tarlib.Errors.OK;
            else
               Set_Pending_Sparse_Length
                 (Archive, Data, Value_First, Value_Last, Result);
               if Result.Code /= Tarlib.Errors.Success then
                  return;
               end if;
            end if;
         elsif Key_Equals (Data, Key_First, Equal_Index - 1, "SCHILY.filetype")
           or else Key_Equals
             (Data, Key_First, Equal_Index - 1, "LIBARCHIVE.sparse")
         then
            Result := Tarlib.Errors.OK;
         elsif Key_Has_Prefix
           (Data, Key_First, Equal_Index - 1, "SCHILY.xattr.")
         then
            if Global then
               Result := Tarlib.Errors.OK;
            else
               Add_Pending_XAttr
                 (Archive, Data, Key_First, Equal_Index - 1,
                  Value_First, Value_Last, Result);
               if Result.Code /= Tarlib.Errors.Success then
                  return;
               end if;
            end if;
         elsif Key_Equals
           (Data, Key_First, Equal_Index - 1, "SCHILY.acl.access")
         then
            if Global then
               Result := Tarlib.Errors.OK;
            else
               Set_Pending_Vendor_Text
                 (Archive, Data, Value_First, Value_Last,
                  Archive.Pending_ACL_Access,
                  Archive.Has_Pending_ACL_Access, Result);
               if Result.Code /= Tarlib.Errors.Success then
                  return;
               end if;
            end if;
         elsif Key_Equals
           (Data, Key_First, Equal_Index - 1, "SCHILY.acl.default")
         then
            if Global then
               Result := Tarlib.Errors.OK;
            else
               Set_Pending_Vendor_Text
                 (Archive, Data, Value_First, Value_Last,
                  Archive.Pending_ACL_Default,
                  Archive.Has_Pending_ACL_Default, Result);
               if Result.Code /= Tarlib.Errors.Success then
                  return;
               end if;
            end if;
         elsif Key_Equals
           (Data, Key_First, Equal_Index - 1, "LIBARCHIVE.fflags")
         then
            if Global then
               Result := Tarlib.Errors.OK;
            else
               Set_Pending_Vendor_Text
                 (Archive, Data, Value_First, Value_Last,
                  Archive.Pending_File_Flags,
                  Archive.Has_Pending_File_Flags, Result);
               if Result.Code /= Tarlib.Errors.Success then
                  return;
               end if;
            end if;
         elsif Key_Equals
           (Data, Key_First, Equal_Index - 1, "GNU.volume.offset")
         then
            if Global then
               Result := Tarlib.Errors.OK;
            else
               Set_Pending_Volume_Offset
                 (Archive, Data, Value_First, Value_Last, Result);
               if Result.Code /= Tarlib.Errors.Success then
                  return;
               end if;
            end if;
         elsif Key_Has_Prefix
           (Data, Key_First, Equal_Index - 1, "GNU.sparse.")
         then
            Result := (Code => Tarlib.Errors.Invalid_Entry_Kind);
            Archive.Current_State := Failed;
            return;
         elsif Equal_Index - Key_First = 4
           and then Data (Key_First) = Character'Pos ('p')
           and then Data (Key_First + 1) = Character'Pos ('a')
         and then Data (Key_First + 2) = Character'Pos ('t')
         and then Data (Key_First + 3) = Character'Pos ('h')
         then
            if Global then
               Result := Tarlib.Errors.OK;
            else
               Set_Pending_Path
                 (Archive, Data, Value_First, Value_Last, Result);
               if Result.Code /= Tarlib.Errors.Success then
                  return;
               end if;
            end if;
         elsif Equal_Index - Key_First = 8
           and then Data (Key_First) = Character'Pos ('l')
           and then Data (Key_First + 1) = Character'Pos ('i')
           and then Data (Key_First + 2) = Character'Pos ('n')
           and then Data (Key_First + 3) = Character'Pos ('k')
           and then Data (Key_First + 4) = Character'Pos ('p')
           and then Data (Key_First + 5) = Character'Pos ('a')
           and then Data (Key_First + 6) = Character'Pos ('t')
           and then Data (Key_First + 7) = Character'Pos ('h')
         then
            if Global then
               Result := Tarlib.Errors.OK;
            else
               Set_Pending_Link_Path
                 (Archive, Data, Value_First, Value_Last, Result);
               if Result.Code /= Tarlib.Errors.Success then
                  return;
               end if;
            end if;
         elsif Equal_Index - Key_First = 4
           and then Data (Key_First) = Character'Pos ('s')
           and then Data (Key_First + 1) = Character'Pos ('i')
           and then Data (Key_First + 2) = Character'Pos ('z')
           and then Data (Key_First + 3) = Character'Pos ('e')
         then
           Set_Pending_Numeric
              (Archive, Data, Value_First, Value_Last, "size", Global, Result);
            if Result.Code /= Tarlib.Errors.Success then
               return;
            end if;
         elsif Equal_Index - Key_First = 5
           and then Data (Key_First) = Character'Pos ('m')
           and then Data (Key_First + 1) = Character'Pos ('t')
           and then Data (Key_First + 2) = Character'Pos ('i')
           and then Data (Key_First + 3) = Character'Pos ('m')
           and then Data (Key_First + 4) = Character'Pos ('e')
         then
           Set_Pending_Numeric
              (Archive, Data, Value_First, Value_Last, "mtime", Global, Result);
            if Result.Code /= Tarlib.Errors.Success then
               return;
            end if;
         elsif Key_Equals (Data, Key_First, Equal_Index - 1, "atime") then
           Set_Pending_Numeric
              (Archive, Data, Value_First, Value_Last, "atime", Global, Result);
            if Result.Code /= Tarlib.Errors.Success then
               return;
            end if;
         elsif Key_Equals (Data, Key_First, Equal_Index - 1, "ctime") then
           Set_Pending_Numeric
              (Archive, Data, Value_First, Value_Last, "ctime", Global, Result);
            if Result.Code /= Tarlib.Errors.Success then
               return;
            end if;
         elsif Equal_Index - Key_First = 3
           and then Data (Key_First) = Character'Pos ('u')
           and then Data (Key_First + 1) = Character'Pos ('i')
           and then Data (Key_First + 2) = Character'Pos ('d')
         then
           Set_Pending_Numeric
              (Archive, Data, Value_First, Value_Last, "uid", Global, Result);
            if Result.Code /= Tarlib.Errors.Success then
               return;
            end if;
         elsif Equal_Index - Key_First = 3
           and then Data (Key_First) = Character'Pos ('g')
           and then Data (Key_First + 1) = Character'Pos ('i')
           and then Data (Key_First + 2) = Character'Pos ('d')
         then
           Set_Pending_Numeric
              (Archive, Data, Value_First, Value_Last, "gid", Global, Result);
            if Result.Code /= Tarlib.Errors.Success then
               return;
            end if;
         elsif Key_Equals (Data, Key_First, Equal_Index - 1, "uname") then
           Set_Pending_Text
              (Archive, Data, Value_First, Value_Last, "uname", Global,
               Result);
            if Result.Code /= Tarlib.Errors.Success then
               return;
            end if;
         elsif Key_Equals (Data, Key_First, Equal_Index - 1, "gname") then
           Set_Pending_Text
              (Archive, Data, Value_First, Value_Last, "gname", Global,
               Result);
            if Result.Code /= Tarlib.Errors.Success then
               return;
            end if;
         elsif Equal_Index - Key_First = 8
           and then Data (Key_First) = Character'Pos ('d')
           and then Data (Key_First + 1) = Character'Pos ('e')
           and then Data (Key_First + 2) = Character'Pos ('v')
           and then Data (Key_First + 3) = Character'Pos ('m')
           and then Data (Key_First + 4) = Character'Pos ('a')
           and then Data (Key_First + 5) = Character'Pos ('j')
           and then Data (Key_First + 6) = Character'Pos ('o')
           and then Data (Key_First + 7) = Character'Pos ('r')
         then
           Set_Pending_Numeric
              (Archive, Data, Value_First, Value_Last, "devmajor", Global,
               Result);
            if Result.Code /= Tarlib.Errors.Success then
               return;
            end if;
         elsif Equal_Index - Key_First = 8
           and then Data (Key_First) = Character'Pos ('d')
           and then Data (Key_First + 1) = Character'Pos ('e')
           and then Data (Key_First + 2) = Character'Pos ('v')
           and then Data (Key_First + 3) = Character'Pos ('m')
           and then Data (Key_First + 4) = Character'Pos ('i')
           and then Data (Key_First + 5) = Character'Pos ('n')
           and then Data (Key_First + 6) = Character'Pos ('o')
           and then Data (Key_First + 7) = Character'Pos ('r')
         then
           Set_Pending_Numeric
              (Archive, Data, Value_First, Value_Last, "devminor", Global,
               Result);
            if Result.Code /= Tarlib.Errors.Success then
               return;
            end if;
         elsif Equal_Index - Key_First = 15
           and then Data (Key_First) = Character'Pos ('S')
           and then Data (Key_First + 1) = Character'Pos ('C')
           and then Data (Key_First + 2) = Character'Pos ('H')
           and then Data (Key_First + 3) = Character'Pos ('I')
           and then Data (Key_First + 4) = Character'Pos ('L')
           and then Data (Key_First + 5) = Character'Pos ('Y')
           and then Data (Key_First + 6) = Character'Pos ('.')
           and then Data (Key_First + 7) = Character'Pos ('d')
           and then Data (Key_First + 8) = Character'Pos ('e')
           and then Data (Key_First + 9) = Character'Pos ('v')
           and then Data (Key_First + 10) = Character'Pos ('m')
           and then Data (Key_First + 11) = Character'Pos ('a')
           and then Data (Key_First + 12) = Character'Pos ('j')
           and then Data (Key_First + 13) = Character'Pos ('o')
           and then Data (Key_First + 14) = Character'Pos ('r')
         then
           Set_Pending_Numeric
              (Archive, Data, Value_First, Value_Last, "devmajor", Global,
               Result);
            if Result.Code /= Tarlib.Errors.Success then
               return;
            end if;
         elsif Equal_Index - Key_First = 15
           and then Data (Key_First) = Character'Pos ('S')
           and then Data (Key_First + 1) = Character'Pos ('C')
           and then Data (Key_First + 2) = Character'Pos ('H')
           and then Data (Key_First + 3) = Character'Pos ('I')
           and then Data (Key_First + 4) = Character'Pos ('L')
           and then Data (Key_First + 5) = Character'Pos ('Y')
           and then Data (Key_First + 6) = Character'Pos ('.')
           and then Data (Key_First + 7) = Character'Pos ('d')
           and then Data (Key_First + 8) = Character'Pos ('e')
           and then Data (Key_First + 9) = Character'Pos ('v')
           and then Data (Key_First + 10) = Character'Pos ('m')
           and then Data (Key_First + 11) = Character'Pos ('i')
           and then Data (Key_First + 12) = Character'Pos ('n')
           and then Data (Key_First + 13) = Character'Pos ('o')
           and then Data (Key_First + 14) = Character'Pos ('r')
         then
           Set_Pending_Numeric
              (Archive, Data, Value_First, Value_Last, "devminor", Global,
               Result);
            if Result.Code /= Tarlib.Errors.Success then
               return;
            end if;
         else
            Set_Pending_Extension_Record
              (Archive, Data, Key_First, Equal_Index - 1, Value_First,
               Value_Last, Global, Result);
            if Result.Code /= Tarlib.Errors.Success then
               return;
            end if;
         end if;

         Position := Record_End + 1;
      end loop;

      Result := Tarlib.Errors.OK;
   end Parse_PAX;

   procedure Read_PAX_Extended_Header
     (Archive : in out Reader;
      Size    : Tarlib.Byte_Count;
      Global  : Boolean;
      Result  : out Tarlib.Errors.Status)
   is
      Data         : Ada.Streams.Stream_Element_Array (1 .. Tarlib.Max_PAX_Data);
      Length       : constant Natural := Natural (Size);
   begin
      if Size > Tarlib.Byte_Count (Tarlib.Max_PAX_Data) then
         Result := (Code => Tarlib.Errors.Invalid_Archive);
         Archive.Current_State := Failed;
         return;
      end if;

      Read_Exact
        (Archive,
         Data (1 .. Ada.Streams.Stream_Element_Offset (Length)),
         Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Parse_PAX (Archive, Data, Length, Global, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Discard
        (Archive,
         Interfaces.Unsigned_64
           (Tarlib.Internal.Padding.Padding_Length (Size)),
         Result);
   end Read_PAX_Extended_Header;

   procedure Read_GNU_Long_Text
     (Archive : in out Reader;
      Size    : Tarlib.Byte_Count;
      Is_Link : Boolean;
      Result  : out Tarlib.Errors.Status)
   is
      Data_Length : Natural := Natural (Size);
      Data        : Ada.Streams.Stream_Element_Array (1 .. Max_Path_Length + 1);
   begin
      if Size = 0 or else Size > Tarlib.Byte_Count (Max_Path_Length + 1) then
         Result := (Code => Tarlib.Errors.Invalid_Archive);
         Archive.Current_State := Failed;
         return;
      end if;

      Read_Exact
        (Archive,
         Data (1 .. Ada.Streams.Stream_Element_Offset (Data_Length)),
         Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      if Data (Ada.Streams.Stream_Element_Offset (Data_Length)) = 0 then
         Data_Length := Data_Length - 1;
      end if;

      if Data_Length = 0 then
         Result := (Code => Tarlib.Errors.Invalid_Archive);
         Archive.Current_State := Failed;
         return;
      elsif Is_Link then
         Set_Pending_Link_Path
           (Archive, Data, 1, Ada.Streams.Stream_Element_Offset (Data_Length),
            Result);
      else
         Set_Pending_Path
           (Archive, Data, 1, Ada.Streams.Stream_Element_Offset (Data_Length),
            Result);
      end if;

      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Discard
        (Archive,
         Interfaces.Unsigned_64
           (Tarlib.Internal.Padding.Padding_Length (Size)),
         Result);
   end Read_GNU_Long_Text;

   function Is_Zero
     (Block : Tarlib.Internal.Constants.Header_Block) return Boolean is
   begin
      for Byte of Block loop
         if Byte /= 0 then
            return False;
         end if;
      end loop;

      return True;
   end Is_Zero;

   procedure Initialize
     (Archive : in out Reader;
      Source  : aliased in out Tarlib.Inputs.Input_Source'Class;
      Result  : out Tarlib.Errors.Status) is
   begin
      if Archive.Current_State /= Uninitialized then
         Result := (Code => Tarlib.Errors.Invalid_State);
         return;
      end if;

      Archive.Source := Source'Unchecked_Access;
      Archive.Current_State := Ready;
      Archive.Remaining_Size := 0;
      Archive.Active_Physical_Size := 0;
      Archive.Remaining_Padding := 0;
      Archive.Active_Logical_Offset := 0;
      Archive.Active_Sparse_Count := 0;
      Archive.Active_Sparse_Index := 1;
      Result := Tarlib.Errors.OK;
   end Initialize;

   procedure Next_Entry
     (Archive   : in out Reader;
      Info      : out Entry_Info;
      Has_Entry : out Boolean;
      Result    : out Tarlib.Errors.Status)
   is
      Header : Tarlib.Internal.Constants.Header_Block;
      Parsed : Tarlib.Internal.Headers.Parsed_Header;
      Link_Status : Tarlib.Errors.Status;
   begin
      Info := (others => <>);
      Has_Entry := False;

      if Archive.Current_State = Failed then
         Result := (Code => Tarlib.Errors.Input_Failure);
         return;
      elsif Archive.Current_State = Finished then
         Result := Tarlib.Errors.OK;
         return;
      elsif Archive.Current_State = Uninitialized then
         Result := (Code => Tarlib.Errors.Invalid_State);
         return;
      elsif Archive.Current_State = Reading_Entry then
         Complete_Active_Entry (Archive, Result);
         if Result.Code /= Tarlib.Errors.Success then
            return;
         end if;
      end if;

      loop
         Read_Exact (Archive, Header, Result);
         if Result.Code /= Tarlib.Errors.Success then
            return;
         elsif Is_Zero (Header) then
            if Archive.Has_Pending_Extension then
               Clear_Pending_Extension (Archive);
               Archive.Current_State := Failed;
               Result := (Code => Tarlib.Errors.Invalid_Archive);
               return;
            end if;

            Archive.Current_State := Finished;
            Result := Tarlib.Errors.OK;
            return;
         end if;

         Tarlib.Internal.Headers.Parse (Header, Parsed, Result);
         if Result.Code /= Tarlib.Errors.Success then
            Archive.Current_State := Failed;
            return;
         end if;

         exit when Parsed.Kind not in Tarlib.Entries.PAX_Extended_Header
                                      | Tarlib.Entries.PAX_Global_Header
                                      | Tarlib.Entries.GNU_Long_Name
                                      | Tarlib.Entries.GNU_Long_Link;

         if Parsed.Kind in Tarlib.Entries.PAX_Extended_Header
                         | Tarlib.Entries.PAX_Global_Header
         then
            Read_PAX_Extended_Header
              (Archive, Parsed.Size,
               Parsed.Kind = Tarlib.Entries.PAX_Global_Header, Result);
         else
            Read_GNU_Long_Text
              (Archive, Parsed.Size, Parsed.Kind = Tarlib.Entries.GNU_Long_Link,
               Result);
         end if;
         if Result.Code /= Tarlib.Errors.Success then
            return;
         end if;

         if Parsed.Kind /= Tarlib.Entries.PAX_Global_Header then
            Archive.Has_Pending_Extension := True;
         end if;
      end loop;

      Info.Path_Text (1 .. Parsed.Path_Length) :=
        Parsed.Path_Text (1 .. Parsed.Path_Length);
      Info.Path_Length := Parsed.Path_Length;
      if Archive.Pending_Path_Length > 0 then
         Info.Path_Text (1 .. Archive.Pending_Path_Length) :=
           Archive.Pending_Path (1 .. Archive.Pending_Path_Length);
         Info.Path_Length := Archive.Pending_Path_Length;
         Archive.Pending_Path_Length := 0;
      end if;
      if Parsed.Link_Length > 0 then
         Info.Link_Text (1 .. Parsed.Link_Length) :=
           Parsed.Link_Text (1 .. Parsed.Link_Length);
         Info.Link_Length := Parsed.Link_Length;
      end if;
      if Archive.Pending_Link_Path_Length > 0 then
         if Parsed.Kind not in Tarlib.Entries.Hard_Link
                          | Tarlib.Entries.Symbolic_Link
         then
            Clear_Pending_Extension (Archive);
            Result := (Code => Tarlib.Errors.Invalid_Entry_Kind);
            Archive.Current_State := Failed;
            return;
         end if;

         Info.Link_Text (1 .. Archive.Pending_Link_Path_Length) :=
           Archive.Pending_Link_Path (1 .. Archive.Pending_Link_Path_Length);
         Info.Link_Length := Archive.Pending_Link_Path_Length;
         Archive.Pending_Link_Path_Length := 0;
      end if;
      if Parsed.Kind in Tarlib.Entries.Hard_Link
                      | Tarlib.Entries.Symbolic_Link
        and then Info.Link_Length = 0
      then
         Result := (Code => Tarlib.Errors.Invalid_Metadata);
         Archive.Current_State := Failed;
         return;
      end if;
      if Parsed.Kind = Tarlib.Entries.Hard_Link then
         Link_Status :=
           Tarlib.Internal.Paths.Validate_Archive_Path
             (Info.Link_Text (1 .. Info.Link_Length));
         if Link_Status.Code /= Tarlib.Errors.Success then
            Result := Link_Status;
            Archive.Current_State := Failed;
            return;
         end if;
      end if;
      Info.Entry_Kind := Parsed.Kind;
      Info.Entry_Size := Parsed.Size;
      Info.Entry_Meta := Parsed.Metadata;
      Info.Device_Info := Parsed.Device;
      Info.Volume_Offset := 0;
      if Parsed.Has_Multi_Volume_Offset then
         Info.Volume_Offset := Parsed.Multi_Volume_Offset;
      end if;
      if Archive.Has_Global_MTime then
         Info.Entry_Meta.MTime := Archive.Global_MTime;
      end if;
      if Archive.Has_Global_ATime then
         Info.Entry_Meta.ATime := Archive.Global_ATime;
      end if;
      if Archive.Has_Global_CTime then
         Info.Entry_Meta.CTime := Archive.Global_CTime;
      end if;
      if Archive.Has_Global_UID then
         Info.Entry_Meta.UID := Archive.Global_UID;
      end if;
      if Archive.Has_Global_GID then
         Info.Entry_Meta.GID := Archive.Global_GID;
      end if;
      if Archive.Has_Global_User_Name then
         Info.Entry_Meta.User_Name := Archive.Global_User_Name;
      end if;
      if Archive.Has_Global_Group_Name then
         Info.Entry_Meta.Group_Name := Archive.Global_Group_Name;
      end if;
      if Archive.Has_Pending_Size then
         if Parsed.Kind in Tarlib.Entries.Regular_File
                         | Tarlib.Entries.Hard_Link
                         | Tarlib.Entries.Multi_Volume
                         | Tarlib.Entries.Incremental_Dump
         then
            Info.Entry_Size := Archive.Pending_Size;
         end if;
         Archive.Has_Pending_Size := False;
      end if;
      if Parsed.Has_Sparse_Map then
         Archive.Pending_Sparse_Count := Parsed.Sparse_Count;
         for Index in 1 .. Parsed.Sparse_Count loop
            Archive.Pending_Sparse_Extents (Index) :=
              (Offset => Parsed.Sparse_Extents (Index).Offset,
               Length => Parsed.Sparse_Extents (Index).Length);
         end loop;
         Archive.Pending_Sparse_Size := Parsed.Sparse_Size;
         Archive.Has_Pending_Sparse_Map := True;
         Archive.Has_Pending_Sparse_Size := True;
         if Parsed.Has_Sparse_Extension then
            Read_Old_GNU_Sparse_Extensions (Archive, Result);
            if Result.Code /= Tarlib.Errors.Success then
               return;
            end if;
         end if;
      end if;
      if Archive.Has_Pending_Sparse_Map
        or else Archive.Has_Pending_Sparse_Size
        or else Archive.Has_Pending_Sparse_Offset
        or else Parsed.Kind = Tarlib.Entries.GNU_Sparse
      then
         declare
            Stored_Size : Tarlib.Byte_Count := 0;
            Last_End    : Tarlib.Byte_Count := 0;
         begin
            if not Archive.Has_Pending_Sparse_Map
              or else not Archive.Has_Pending_Sparse_Size
              or else Archive.Has_Pending_Sparse_Offset
              or else Parsed.Kind not in Tarlib.Entries.Regular_File
                                    | Tarlib.Entries.GNU_Sparse
            then
               Clear_Pending_Extension (Archive);
               Result := (Code => Tarlib.Errors.Invalid_Entry_Kind);
               Archive.Current_State := Failed;
               return;
            end if;

            for Index in 1 .. Archive.Pending_Sparse_Count loop
               declare
                  Extent : constant Sparse_Extent :=
                    Archive.Pending_Sparse_Extents (Index);
               begin
                  if Extent.Length
                    > Tarlib.Byte_Count'Last - Stored_Size
                    or else Extent.Length
                      > Tarlib.Byte_Count'Last - Extent.Offset
                  then
                     Clear_Pending_Extension (Archive);
                     Result := (Code => Tarlib.Errors.Invalid_Metadata);
                     Archive.Current_State := Failed;
                     return;
                  end if;

                  Stored_Size := Stored_Size + Extent.Length;
                  Last_End := Extent.Offset + Extent.Length;
               end;
            end loop;

            if Stored_Size /= Parsed.Size
              or else Last_End > Archive.Pending_Sparse_Size
            then
               Clear_Pending_Extension (Archive);
               Result := (Code => Tarlib.Errors.Invalid_Metadata);
               Archive.Current_State := Failed;
               return;
            end if;

            Info.Entry_Kind := Tarlib.Entries.Regular_File;
            Info.Entry_Size := Archive.Pending_Sparse_Size;
         end;
      end if;
      if Archive.Has_Pending_MTime then
         Info.Entry_Meta.MTime := Archive.Pending_MTime;
         Archive.Has_Pending_MTime := False;
      end if;
      if Archive.Has_Pending_ATime then
         Info.Entry_Meta.ATime := Archive.Pending_ATime;
         Archive.Has_Pending_ATime := False;
      end if;
      if Archive.Has_Pending_CTime then
         Info.Entry_Meta.CTime := Archive.Pending_CTime;
         Archive.Has_Pending_CTime := False;
      end if;
      if Archive.Has_Pending_UID then
         Info.Entry_Meta.UID := Archive.Pending_UID;
         Archive.Has_Pending_UID := False;
      end if;
      if Archive.Has_Pending_GID then
         Info.Entry_Meta.GID := Archive.Pending_GID;
         Archive.Has_Pending_GID := False;
      end if;
      if Archive.Has_Pending_User_Name then
         Info.Entry_Meta.User_Name := Archive.Pending_User_Name;
         Archive.Has_Pending_User_Name := False;
      end if;
      if Archive.Has_Pending_Group_Name then
         Info.Entry_Meta.Group_Name := Archive.Pending_Group_Name;
         Archive.Has_Pending_Group_Name := False;
      end if;
      if Archive.Has_Pending_Volume_Offset then
         if Parsed.Kind /= Tarlib.Entries.Multi_Volume then
            Clear_Pending_Extension (Archive);
            Result := (Code => Tarlib.Errors.Invalid_Entry_Kind);
            Archive.Current_State := Failed;
            return;
         end if;

         Info.Volume_Offset := Archive.Pending_Volume_Offset;
         Archive.Has_Pending_Volume_Offset := False;
      end if;
      if Archive.Pending_Extension_Count > 0 then
         Info.Extension_Count := Archive.Pending_Extension_Count;
         Info.Extension_Keys (1 .. Archive.Pending_Extension_Count) :=
           Archive.Pending_Extension_Keys (1 .. Archive.Pending_Extension_Count);
         Info.Extension_Values (1 .. Archive.Pending_Extension_Count) :=
           Archive.Pending_Extension_Values
             (1 .. Archive.Pending_Extension_Count);
         Archive.Pending_Extension_Count := 0;
      end if;
      if Archive.Pending_XAttr_Count > 0 then
         Info.XAttr_Count_Value := Archive.Pending_XAttr_Count;
         Info.XAttr_Names (1 .. Archive.Pending_XAttr_Count) :=
           Archive.Pending_XAttr_Names (1 .. Archive.Pending_XAttr_Count);
         Info.XAttr_Values (1 .. Archive.Pending_XAttr_Count) :=
           Archive.Pending_XAttr_Values (1 .. Archive.Pending_XAttr_Count);
         Archive.Pending_XAttr_Count := 0;
      end if;
      if Archive.Has_Pending_ACL_Access then
         Info.ACL_Access_Value := Archive.Pending_ACL_Access;
         Info.Has_ACL_Access := True;
         Archive.Has_Pending_ACL_Access := False;
      end if;
      if Archive.Has_Pending_ACL_Default then
         Info.ACL_Default_Value := Archive.Pending_ACL_Default;
         Info.Has_ACL_Default := True;
         Archive.Has_Pending_ACL_Default := False;
      end if;
      if Archive.Has_Pending_File_Flags then
         Info.File_Flags_Value := Archive.Pending_File_Flags;
         Info.Has_File_Flags := True;
         Archive.Has_Pending_File_Flags := False;
      end if;
      if Archive.Has_Pending_Device_Major
        or else Archive.Has_Pending_Device_Minor
      then
         if Parsed.Kind not in Tarlib.Entries.Character_Device
                          | Tarlib.Entries.Block_Device
         then
            Clear_Pending_Extension (Archive);
            Result := (Code => Tarlib.Errors.Invalid_Entry_Kind);
            Archive.Current_State := Failed;
            return;
         end if;

         if Archive.Has_Pending_Device_Major then
            Info.Device_Info.Major := Archive.Pending_Device_Major;
            Archive.Has_Pending_Device_Major := False;
         end if;
         if Archive.Has_Pending_Device_Minor then
            Info.Device_Info.Minor := Archive.Pending_Device_Minor;
            Archive.Has_Pending_Device_Minor := False;
         end if;
      end if;
      Archive.Has_Pending_Extension := False;

      Archive.Active_Kind := Info.Entry_Kind;
      Archive.Remaining_Size := Info.Entry_Size;
      Archive.Active_Logical_Offset := 0;
      Archive.Active_Sparse_Count := Archive.Pending_Sparse_Count;
      if Archive.Active_Sparse_Count > 0 then
         Archive.Active_Sparse_Extents (1 .. Archive.Active_Sparse_Count) :=
           Archive.Pending_Sparse_Extents (1 .. Archive.Active_Sparse_Count);
         Archive.Active_Physical_Size := Parsed.Size;
         Info.Sparse_Count := Archive.Active_Sparse_Count;
         Info.Sparse_Logical_Size_Value := Info.Entry_Size;
         Info.Sparse_Physical_Size_Value := Parsed.Size;
         Info.Sparse_Extent_Values (1 .. Archive.Active_Sparse_Count) :=
           Archive.Active_Sparse_Extents (1 .. Archive.Active_Sparse_Count);
         Archive.Remaining_Padding :=
           Tarlib.Internal.Padding.Padding_Length (Parsed.Size);
      else
         Archive.Active_Physical_Size := Info.Entry_Size;
         Info.Sparse_Logical_Size_Value := Info.Entry_Size;
         Info.Sparse_Physical_Size_Value := Info.Entry_Size;
         Archive.Remaining_Padding :=
           Tarlib.Internal.Padding.Padding_Length (Info.Entry_Size);
      end if;
      Archive.Active_Sparse_Index := 1;
      Archive.Pending_Sparse_Count := 0;
      Archive.Pending_Sparse_Size := 0;
      Archive.Has_Pending_Sparse_Size := False;
      Archive.Has_Pending_Sparse_Map := False;
      Archive.Current_State := Reading_Entry;
      Has_Entry := True;
      Result := Tarlib.Errors.OK;
   end Next_Entry;

   procedure Read
     (Archive : in out Reader;
      Data    : out Ada.Streams.Stream_Element_Array;
      Last    : out Ada.Streams.Stream_Element_Offset;
      Result  : out Tarlib.Errors.Status)
   is
      Requested : constant Interfaces.Unsigned_64 :=
        Interfaces.Unsigned_64 (Data'Length);
      Count     : constant Interfaces.Unsigned_64 :=
        Interfaces.Unsigned_64'Min (Requested, Archive.Remaining_Size);
      Cursor    : Ada.Streams.Stream_Element_Offset := Data'First;
      Target    : Ada.Streams.Stream_Element_Offset;
      Chunk     : Tarlib.Byte_Count;
   begin
      Last := Data'First - 1;

      if Archive.Current_State = Failed then
         Result := (Code => Tarlib.Errors.Input_Failure);
         return;
      elsif Archive.Current_State = Finished then
         Result := (Code => Tarlib.Errors.Already_Finished);
         return;
      elsif Archive.Current_State /= Reading_Entry then
         Result := (Code => Tarlib.Errors.Invalid_State);
         return;
      elsif Archive.Active_Kind not in Tarlib.Entries.Regular_File
                                  | Tarlib.Entries.Multi_Volume
                                  | Tarlib.Entries.Incremental_Dump
      then
         Result := (Code => Tarlib.Errors.Invalid_Entry_Kind);
         return;
      elsif Count = 0 then
         Result := Tarlib.Errors.OK;
         return;
      end if;

      Target := Data'First + Ada.Streams.Stream_Element_Offset (Count) - 1;
      if Archive.Active_Sparse_Count = 0 then
         Read_Exact (Archive, Data (Data'First .. Target), Result);
         if Result.Code /= Tarlib.Errors.Success then
            return;
         end if;

         Archive.Remaining_Size := Archive.Remaining_Size - Count;
         Archive.Active_Physical_Size := Archive.Active_Physical_Size - Count;
      else
         while Cursor <= Target loop
            while Archive.Active_Sparse_Index <= Archive.Active_Sparse_Count
              and then Archive.Active_Logical_Offset
                >= Archive.Active_Sparse_Extents
                     (Archive.Active_Sparse_Index).Offset
                   + Archive.Active_Sparse_Extents
                       (Archive.Active_Sparse_Index).Length
            loop
               Archive.Active_Sparse_Index := Archive.Active_Sparse_Index + 1;
            end loop;

            if Archive.Active_Sparse_Index > Archive.Active_Sparse_Count
              or else Archive.Active_Logical_Offset
                < Archive.Active_Sparse_Extents
                    (Archive.Active_Sparse_Index).Offset
            then
               declare
                  Logical_End : constant Tarlib.Byte_Count :=
                    Archive.Active_Logical_Offset + Archive.Remaining_Size;
                  Hole_End : Tarlib.Byte_Count := Logical_End;
                  Available : constant Tarlib.Byte_Count :=
                    Tarlib.Byte_Count (Target - Cursor + 1);
               begin
                  if Archive.Active_Sparse_Index <= Archive.Active_Sparse_Count
                  then
                     Hole_End :=
                       Tarlib.Byte_Count'Min
                         (Hole_End,
                          Archive.Active_Sparse_Extents
                            (Archive.Active_Sparse_Index).Offset);
                  end if;

                  Chunk :=
                    Tarlib.Byte_Count'Min
                      (Available, Hole_End - Archive.Active_Logical_Offset);
                  if Chunk = 0 then
                     Result := (Code => Tarlib.Errors.Invalid_Archive);
                     Archive.Current_State := Failed;
                     return;
                  end if;

                  Data
                    (Cursor
                     .. Cursor + Ada.Streams.Stream_Element_Offset (Chunk) - 1)
                    := [others => 0];
                  Cursor := Cursor + Ada.Streams.Stream_Element_Offset (Chunk);
                  Archive.Active_Logical_Offset :=
                    Archive.Active_Logical_Offset + Chunk;
                  Archive.Remaining_Size := Archive.Remaining_Size - Chunk;
               end;
            else
               declare
                  Extent : constant Sparse_Extent :=
                    Archive.Active_Sparse_Extents (Archive.Active_Sparse_Index);
                  Extent_End : constant Tarlib.Byte_Count :=
                    Extent.Offset + Extent.Length;
                  Available : constant Tarlib.Byte_Count :=
                    Tarlib.Byte_Count (Target - Cursor + 1);
               begin
                  Chunk :=
                    Tarlib.Byte_Count'Min
                      (Available, Extent_End - Archive.Active_Logical_Offset);
                  if Chunk = 0
                    or else Chunk > Archive.Active_Physical_Size
                  then
                     Result := (Code => Tarlib.Errors.Invalid_Archive);
                     Archive.Current_State := Failed;
                     return;
                  end if;

                  Read_Exact
                    (Archive,
                     Data
                       (Cursor
                        .. Cursor
                           + Ada.Streams.Stream_Element_Offset (Chunk) - 1),
                     Result);
                  if Result.Code /= Tarlib.Errors.Success then
                     return;
                  end if;

                  Cursor := Cursor + Ada.Streams.Stream_Element_Offset (Chunk);
                  Archive.Active_Logical_Offset :=
                    Archive.Active_Logical_Offset + Chunk;
                  Archive.Remaining_Size := Archive.Remaining_Size - Chunk;
                  Archive.Active_Physical_Size :=
                    Archive.Active_Physical_Size - Chunk;
               end;
            end if;
         end loop;
      end if;

      Last := Target;
      Result := Tarlib.Errors.OK;
   end Read;

   procedure Skip_Entry
     (Archive : in out Reader;
      Result  : out Tarlib.Errors.Status) is
   begin
      if Archive.Current_State = Failed then
         Result := (Code => Tarlib.Errors.Input_Failure);
         return;
      elsif Archive.Current_State = Finished then
         Result := (Code => Tarlib.Errors.Already_Finished);
         return;
      elsif Archive.Current_State /= Reading_Entry then
         Result := (Code => Tarlib.Errors.Invalid_State);
         return;
      end if;

      Complete_Active_Entry (Archive, Result);
   end Skip_Entry;

   procedure Read_Incremental_Dump
     (Archive : in out Reader;
      Listing : out Incremental_Listing;
      Result  : out Tarlib.Errors.Status)
   is
      Data : Ada.Streams.Stream_Element_Array (1 .. Tarlib.Max_PAX_Data);
      Last : Ada.Streams.Stream_Element_Offset;
      Length : Natural;
      Position : Ada.Streams.Stream_Element_Offset := 1;
      Record_First : Ada.Streams.Stream_Element_Offset;
      Record_Last  : Ada.Streams.Stream_Element_Offset;
      Slot         : Natural;
   begin
      Listing := (others => <>);

      if Archive.Current_State = Failed then
         Result := (Code => Tarlib.Errors.Input_Failure);
         return;
      elsif Archive.Current_State = Finished then
         Result := (Code => Tarlib.Errors.Already_Finished);
         return;
      elsif Archive.Current_State /= Reading_Entry then
         Result := (Code => Tarlib.Errors.Invalid_State);
         return;
      elsif Archive.Active_Kind /= Tarlib.Entries.Incremental_Dump then
         Result := (Code => Tarlib.Errors.Invalid_Entry_Kind);
         return;
      elsif Archive.Remaining_Size > Tarlib.Byte_Count (Tarlib.Max_PAX_Data)
      then
         Result := (Code => Tarlib.Errors.Invalid_Metadata);
         Archive.Current_State := Failed;
         return;
      end if;

      Length := Natural (Archive.Remaining_Size);
      if Length > 0 then
         Read
           (Archive,
            Data (1 .. Ada.Streams.Stream_Element_Offset (Length)),
            Last, Result);
         if Result.Code /= Tarlib.Errors.Success then
            return;
         elsif Last /= Ada.Streams.Stream_Element_Offset (Length) then
            Result := (Code => Tarlib.Errors.Invalid_Archive);
            Archive.Current_State := Failed;
            return;
         end if;
      end if;

      while Position <= Ada.Streams.Stream_Element_Offset (Length) loop
         exit when Data (Position) = 0;
         Record_First := Position;
         while Position <= Ada.Streams.Stream_Element_Offset (Length)
           and then Data (Position) /= 0
         loop
            Position := Position + 1;
         end loop;

         if Position > Ada.Streams.Stream_Element_Offset (Length)
           or else Position = Record_First
         then
            Result := (Code => Tarlib.Errors.Invalid_Archive);
            Archive.Current_State := Failed;
            return;
         end if;

         if Data (Record_First) not in Character'Pos ('Y')
                                      | Character'Pos ('N')
         then
            Result := (Code => Tarlib.Errors.Invalid_Metadata);
            Archive.Current_State := Failed;
            return;
         end if;

         Record_Last := Position - 1;
         if Record_Last = Record_First
           or else Record_Last - Record_First > Max_Path_Length
           or else Listing.Record_Count = Max_Incremental_Records
         then
            Result := (Code => Tarlib.Errors.Invalid_Metadata);
            Archive.Current_State := Failed;
            return;
         end if;

         Slot := Listing.Record_Count + 1;
         Listing.Records (Slot).Is_Directory :=
           Data (Record_First) = Character'Pos ('Y');
         Listing.Records (Slot).Path_Length := Natural (Record_Last - Record_First);
         for Offset in 1 .. Listing.Records (Slot).Path_Length loop
            Listing.Records (Slot).Path_Text (Offset) :=
              Character'Val
                (Data
                   (Record_First + Ada.Streams.Stream_Element_Offset (Offset)));
         end loop;
         Listing.Record_Count := Slot;
         Position := Position + 1;
      end loop;

      Result := Tarlib.Errors.OK;
   end Read_Incremental_Dump;

   function State (Archive : Reader) return Reader_State is
   begin
      return Archive.Current_State;
   end State;

   function At_End (Archive : Reader) return Boolean is
   begin
      return Archive.Current_State = Finished;
   end At_End;

   function Path (Info : Entry_Info) return String is
   begin
      return Info.Path_Text (1 .. Info.Path_Length);
   end Path;

   function Kind (Info : Entry_Info) return Tarlib.Entries.Entry_Kind is
   begin
      return Info.Entry_Kind;
   end Kind;

   function Size (Info : Entry_Info) return Tarlib.Byte_Count is
   begin
      return Info.Entry_Size;
   end Size;

   function Link_Path (Info : Entry_Info) return String is
   begin
      return Info.Link_Text (1 .. Info.Link_Length);
   end Link_Path;

   function Device (Info : Entry_Info) return Tarlib.Entries.Device_Numbers is
   begin
      return Info.Device_Info;
   end Device;

   function Multi_Volume_Offset
     (Info : Entry_Info) return Tarlib.Entries.Archive_Offset is
   begin
      return Info.Volume_Offset;
   end Multi_Volume_Offset;

   function Sparse_Extent_Count (Info : Entry_Info) return Natural is
   begin
      return Info.Sparse_Count;
   end Sparse_Extent_Count;

   function Sparse_Logical_Size (Info : Entry_Info) return Tarlib.Byte_Count is
   begin
      return Info.Sparse_Logical_Size_Value;
   end Sparse_Logical_Size;

   function Sparse_Physical_Size (Info : Entry_Info) return Tarlib.Byte_Count is
   begin
      return Info.Sparse_Physical_Size_Value;
   end Sparse_Physical_Size;

   function Sparse_Extent_Offset
     (Info  : Entry_Info;
      Index : Positive) return Tarlib.Byte_Count is
   begin
      if Index > Info.Sparse_Count then
         return 0;
      else
         return Info.Sparse_Extent_Values (Index).Offset;
      end if;
   end Sparse_Extent_Offset;

   function Sparse_Extent_Length
     (Info  : Entry_Info;
      Index : Positive) return Tarlib.Byte_Count is
   begin
      if Index > Info.Sparse_Count then
         return 0;
      else
         return Info.Sparse_Extent_Values (Index).Length;
      end if;
   end Sparse_Extent_Length;

   function Metadata (Info : Entry_Info) return Tarlib.Entries.Metadata is
   begin
      return Info.Entry_Meta;
   end Metadata;

   function Extended_Record_Count (Info : Entry_Info) return Natural is
   begin
      return Info.Extension_Count;
   end Extended_Record_Count;

   function Extended_Key
     (Info  : Entry_Info;
      Index : Positive) return String is
   begin
      if Index > Info.Extension_Count then
         return "";
      else
         return Tarlib.Entries.Text (Info.Extension_Keys (Index));
      end if;
   end Extended_Key;

   function Extended_Value
     (Info  : Entry_Info;
      Index : Positive) return String is
   begin
      if Index > Info.Extension_Count then
         return "";
      else
         return Tarlib.Entries.Text (Info.Extension_Values (Index));
      end if;
   end Extended_Value;

   function XAttr_Count (Info : Entry_Info) return Natural is
   begin
      return Info.XAttr_Count_Value;
   end XAttr_Count;

   function XAttr_Name
     (Info  : Entry_Info;
      Index : Positive) return String is
   begin
      if Index > Info.XAttr_Count_Value then
         return "";
      else
         return Tarlib.Entries.Text (Info.XAttr_Names (Index));
      end if;
   end XAttr_Name;

   function XAttr_Value
     (Info  : Entry_Info;
      Index : Positive) return String is
   begin
      if Index > Info.XAttr_Count_Value then
         return "";
      else
         return Tarlib.Entries.Text (Info.XAttr_Values (Index));
      end if;
   end XAttr_Value;

   function ACL_Access (Info : Entry_Info) return String is
   begin
      if Info.Has_ACL_Access then
         return Tarlib.Entries.Text (Info.ACL_Access_Value);
      else
         return "";
      end if;
   end ACL_Access;

   function ACL_Default (Info : Entry_Info) return String is
   begin
      if Info.Has_ACL_Default then
         return Tarlib.Entries.Text (Info.ACL_Default_Value);
      else
         return "";
      end if;
   end ACL_Default;

   function File_Flags (Info : Entry_Info) return String is
   begin
      if Info.Has_File_Flags then
         return Tarlib.Entries.Text (Info.File_Flags_Value);
      else
         return "";
      end if;
   end File_Flags;

   function Incremental_Record_Count
     (Listing : Incremental_Listing) return Natural is
   begin
      return Listing.Record_Count;
   end Incremental_Record_Count;

   function Incremental_Record_Path
     (Listing : Incremental_Listing;
      Index   : Positive) return String is
   begin
      if Index > Listing.Record_Count then
         return "";
      else
         return Listing.Records (Index).Path_Text
           (1 .. Listing.Records (Index).Path_Length);
      end if;
   end Incremental_Record_Path;

   function Incremental_Record_Is_Directory
     (Listing : Incremental_Listing;
      Index   : Positive) return Boolean is
   begin
      return Index <= Listing.Record_Count
        and then Listing.Records (Index).Is_Directory;
   end Incremental_Record_Is_Directory;
end Tarlib.Readers;
