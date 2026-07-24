with Ada.Streams;
with Tarlib;
with Tarlib.Entries;
with Tarlib.Errors;
with Tarlib.Outputs;

package Tarlib.Writers
  with Preelaborate
is
   --  Sequential blocking write-only TAR archive writer.

   type Writer_State is
     (Uninitialized, Ready, Writing_Entry, Finished, Failed);
   --  Explicit writer lifecycle state.

   type Writer is tagged limited private;
   --  Writer state. The writer does not own the output sink.

   procedure Initialize
     (Archive     : in out Writer;
      Destination : aliased in out Tarlib.Outputs.Output_Sink'Class;
      Result      : out Tarlib.Errors.Status);
   --  Attach a caller-owned output sink and enter Ready.
   --  @param Archive Writer to initialize; must be Uninitialized.
   --  @param Destination Sink that must outlive Archive or any later calls.
   --  @param Result Success or Invalid_State.

   procedure Begin_Entry
     (Archive  : in out Writer;
      Path     : String;
      Kind     : Tarlib.Entries.Entry_Kind;
      Size     : Tarlib.Byte_Count;
      Metadata : Tarlib.Entries.Metadata;
      Result   : out Tarlib.Errors.Status);
   --  Emit an entry header and enter Writing_Entry.
   --  @param Archive Ready writer.
   --  @param Path Archive-relative USTAR path.
   --  @param Kind Supported entry kind.
   --  @param Size Declared regular-file size or zero for directories.
   --  @param Metadata Deterministic metadata to encode.
   --  @param Result Success or validation/output failure.

   procedure Begin_File
     (Archive  : in out Writer;
      Path     : String;
      Size     : Tarlib.Byte_Count;
      Result   : out Tarlib.Errors.Status);
   --  Begin a regular file with deterministic default metadata.
   --  @param Archive Ready writer.
   --  @param Path Archive-relative USTAR path.
   --  @param Size Declared file size.
   --  @param Result Success or validation/output failure.

   procedure Add_Directory
     (Archive : in out Writer;
      Path    : String;
      Result  : out Tarlib.Errors.Status);
   --  Add an explicit directory entry with default metadata.
   --  @param Archive Ready writer.
   --  @param Path Archive-relative USTAR path.
   --  @param Result Success or validation/output failure.

   procedure Write
     (Archive : in out Writer;
      Data    : Ada.Streams.Stream_Element_Array;
      Result  : out Tarlib.Errors.Status);
   --  Append content bytes to the active regular-file entry.
   --  @param Archive Writer in Writing_Entry for a regular file.
   --  @param Data Content bytes; empty chunks are allowed.
   --  @param Result Success, Too_Much_Entry_Data, or output failure.

   procedure End_Entry
     (Archive : in out Writer;
      Result  : out Tarlib.Errors.Status);
   --  Complete the active entry and emit padding after exact-size completion.
   --  @param Archive Writer in Writing_Entry.
   --  @param Result Success, Too_Little_Entry_Data, or output failure.

   procedure Finish
     (Archive : in out Writer;
      Result  : out Tarlib.Errors.Status);
   --  Emit two zero terminator blocks and enter Finished.
   --  @param Archive Ready writer.
   --  @param Result Success, Already_Finished, invalid state, or output failure.

   function State (Archive : Writer) return Writer_State;
   --  Return the current writer state.
   --  @param Archive Writer to inspect.
   --  @return Current state.

private
   type Output_Sink_Access is access all Tarlib.Outputs.Output_Sink'Class;

   type Writer is tagged limited record
      Current_State : Writer_State := Uninitialized;
      Destination   : Output_Sink_Access := null;
      Active_Kind   : Tarlib.Entries.Entry_Kind := Tarlib.Entries.Regular_File;
      Declared_Size : Tarlib.Byte_Count := 0;
      Written_Size  : Tarlib.Byte_Count := 0;
   end record;
end Tarlib.Writers;
