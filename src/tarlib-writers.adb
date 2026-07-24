with Ada.Streams;
with Interfaces;
with Tarlib.Internal.Constants;
with Tarlib.Internal.Headers;
with Tarlib.Internal.Padding;

package body Tarlib.Writers is
   use type Ada.Streams.Stream_Element_Offset;
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

   procedure Write_Block
     (Archive : in out Writer;
      Block   : Tarlib.Internal.Constants.Header_Block;
      Result  : out Tarlib.Errors.Status) is
   begin
      Archive.Destination.Write
        (Ada.Streams.Stream_Element_Array (Block), Result);
      Mark_Output_Failure (Archive, Result);
   end Write_Block;

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

      Tarlib.Internal.Headers.Build
        (Path, Kind, Size, Metadata, Header, Result);
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
      Result   : out Tarlib.Errors.Status) is
   begin
      Begin_Entry
        (Archive, Path, Tarlib.Entries.Regular_File, Size,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File), Result);
   end Begin_File;

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
      elsif Archive.Active_Kind /= Tarlib.Entries.Regular_File then
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
      Block   : Tarlib.Internal.Constants.Header_Block :=
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
