package body Tarlib.Entries is
   function Default_Metadata (Kind : Entry_Kind) return Metadata is
   begin
      case Kind is
         when Regular_File =>
            return
              (Mode  => Default_File_Mode,
               UID   => Default_Owner,
               GID   => Default_Owner,
               MTime => Default_Timestamp);
         when Directory =>
            return
              (Mode  => Default_Directory_Mode,
               UID   => Default_Owner,
               GID   => Default_Owner,
               MTime => Default_Timestamp);
      end case;
   end Default_Metadata;
end Tarlib.Entries;
