package body Tarlib.Entries is
   Empty_Text : constant Metadata_Text := (others => <>);

   function Default_Metadata (Kind : Entry_Kind) return Metadata is
   begin
      case Kind is
         when Regular_File | Hard_Link | Multi_Volume =>
            return
              (Mode  => Default_File_Mode,
               UID   => Default_Owner,
               GID   => Default_Owner,
               MTime => Default_Timestamp,
               ATime => Default_Timestamp,
               CTime => Default_Timestamp,
               User_Name => Empty_Text,
               Group_Name => Empty_Text);
         when Directory | Incremental_Dump =>
            return
              (Mode  => Default_Directory_Mode,
               UID   => Default_Owner,
               GID   => Default_Owner,
               MTime => Default_Timestamp,
               ATime => Default_Timestamp,
               CTime => Default_Timestamp,
               User_Name => Empty_Text,
               Group_Name => Empty_Text);
         when Symbolic_Link =>
            return
              (Mode  => Default_Link_Mode,
               UID   => Default_Owner,
               GID   => Default_Owner,
               MTime => Default_Timestamp,
               ATime => Default_Timestamp,
               CTime => Default_Timestamp,
               User_Name => Empty_Text,
               Group_Name => Empty_Text);
         when Character_Device
            | Block_Device
            | FIFO
            | PAX_Extended_Header
            | PAX_Global_Header
            | GNU_Long_Name
            | GNU_Long_Link
            | GNU_Sparse
            | Volume_Label =>
            return
              (Mode  => Default_Special_Mode,
               UID   => Default_Owner,
               GID   => Default_Owner,
               MTime => Default_Timestamp,
               ATime => Default_Timestamp,
               CTime => Default_Timestamp,
               User_Name => Empty_Text,
               Group_Name => Empty_Text);
      end case;
   end Default_Metadata;

   function Text (Value : Metadata_Text) return String is
   begin
      return Value.Data (1 .. Value.Length);
   end Text;

   procedure Set_Text
     (Value  : in out Metadata_Text;
      Text   : String;
      Result : out Tarlib.Errors.Status) is
   begin
      if Text'Length > Max_Metadata_Text_Length then
         Result := (Code => Tarlib.Errors.Invalid_Metadata);
         return;
      end if;

      for Character_Value of Text loop
         if Character_Value = Character'Val (0) then
            Result := (Code => Tarlib.Errors.Invalid_Metadata);
            return;
         end if;
      end loop;

      Value.Data := [others => Character'Val (0)];
      Value.Length := Text'Length;
      if Text'Length > 0 then
         Value.Data (1 .. Text'Length) := Text;
      end if;
      Result := Tarlib.Errors.OK;
   end Set_Text;
end Tarlib.Entries;
