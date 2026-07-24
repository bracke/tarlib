with Ada.Command_Line;
with Ada.Text_IO;

with Tarlib.Entries;
with Tarlib.Errors;
with Tarlib.Files;
with Tarlib.Readers;

procedure Read_Archive is
   use type Tarlib.Errors.Status_Code;

   function Archive_Path return String is
   begin
      if Ada.Command_Line.Argument_Count >= 1 then
         return Ada.Command_Line.Argument (1);
      else
         return "example.tar";
      end if;
   end Archive_Path;

   function Kind_Name (Kind : Tarlib.Entries.Entry_Kind) return String is
   begin
      case Kind is
         when Tarlib.Entries.Regular_File =>
            return "file";
         when Tarlib.Entries.Directory =>
            return "directory";
         when Tarlib.Entries.Hard_Link =>
            return "hard-link";
         when Tarlib.Entries.Symbolic_Link =>
            return "symbolic-link";
         when Tarlib.Entries.Character_Device =>
            return "character-device";
         when Tarlib.Entries.Block_Device =>
            return "block-device";
         when Tarlib.Entries.FIFO =>
            return "fifo";
         when Tarlib.Entries.PAX_Extended_Header =>
            return "pax";
         when Tarlib.Entries.PAX_Global_Header =>
            return "global-pax";
         when Tarlib.Entries.GNU_Long_Name =>
            return "gnu-long-name";
         when Tarlib.Entries.GNU_Long_Link =>
            return "gnu-long-link";
         when Tarlib.Entries.GNU_Sparse =>
            return "gnu-sparse";
         when Tarlib.Entries.Multi_Volume =>
            return "multi-volume";
         when Tarlib.Entries.Incremental_Dump =>
            return "incremental-dump";
         when Tarlib.Entries.Volume_Label =>
            return "volume-label";
      end case;
   end Kind_Name;

   Source    : aliased Tarlib.Files.File_Input_Source;
   Reader    : Tarlib.Readers.Reader;
   Info      : Tarlib.Readers.Entry_Info;
   Result    : Tarlib.Errors.Status;
   Has_Entry : Boolean;
begin
   Tarlib.Files.Open_Read (Source, Archive_Path, Result);
   if Result.Code /= Tarlib.Errors.Success then
      Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, "could not open archive");
      return;
   end if;

   Tarlib.Readers.Initialize (Reader, Source, Result);
   if Result.Code /= Tarlib.Errors.Success then
      Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, "could not initialize reader");
      return;
   end if;

   loop
      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      exit when Result.Code /= Tarlib.Errors.Success or else not Has_Entry;

      Ada.Text_IO.Put_Line
        (Kind_Name (Tarlib.Readers.Kind (Info))
         & " "
         & Tarlib.Readers.Path (Info)
         & " size="
         & Tarlib.Byte_Count'Image (Tarlib.Readers.Size (Info)));

      Tarlib.Readers.Skip_Entry (Reader, Result);
      exit when Result.Code /= Tarlib.Errors.Success;
   end loop;

   if Result.Code /= Tarlib.Errors.Success then
      Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, "archive read failed");
   end if;

   Tarlib.Files.Close (Source, Result);
end Read_Archive;
