with Ada.Streams;
with Tarlib.Entries;
with Tarlib.Errors;
with Tarlib.Outputs;

package Tarlib.Writers
  with Preelaborate
is
   --  Sequential blocking TAR archive writer.

   type Writer_State is
     (Uninitialized, Ready, Writing_Entry, Finished, Failed);
   --  Explicit writer lifecycle state.

   type Writer is tagged limited private;
   --  Writer state. The writer does not own the output sink.

   type Sparse_Format is
     (GNU_PAX_Sparse,
      Star_PAX_Sparse,
      Libarchive_PAX_Sparse,
      Old_GNU_Sparse);

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
   --  Emit a generic data or directory header and enter Writing_Entry.
   --  @param Archive Ready writer.
   --  @param Path Archive-relative USTAR path.
   --  @param Kind Regular_File, Directory, Multi_Volume, Incremental_Dump,
   --  or Volume_Label.
   --  @param Size Declared data size or zero for directories.
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

   procedure Begin_Sparse_File
     (Archive      : in out Writer;
      Path         : String;
      Logical_Size : Tarlib.Byte_Count;
      Extents      : Tarlib.Entries.Sparse_Extent_Array;
      Format       : Sparse_Format;
      Metadata     : Tarlib.Entries.Metadata;
      Result       : out Tarlib.Errors.Status);
   --  Begin a sparse regular file. Callers then write exactly the
   --  concatenated bytes for Extents, not the logical holes.

   procedure Begin_Sparse_File
     (Archive      : in out Writer;
      Path         : String;
      Logical_Size : Tarlib.Byte_Count;
      Extents      : Tarlib.Entries.Sparse_Extent_Array;
      Metadata     : Tarlib.Entries.Metadata;
      Result       : out Tarlib.Errors.Status);
   --  Begin a GNU PAX sparse regular file with caller-supplied metadata.

   procedure Begin_Sparse_File
     (Archive      : in out Writer;
      Path         : String;
      Logical_Size : Tarlib.Byte_Count;
      Extents      : Tarlib.Entries.Sparse_Extent_Array;
      Result       : out Tarlib.Errors.Status);
   --  Begin a sparse file with deterministic default metadata.

   procedure Add_Directory
     (Archive : in out Writer;
      Path    : String;
      Result  : out Tarlib.Errors.Status);
   --  Add an explicit directory entry with default metadata.
   --  @param Archive Ready writer.
   --  @param Path Archive-relative USTAR path.
   --  @param Result Success or validation/output failure.

   procedure Add_Link
     (Archive   : in out Writer;
      Path      : String;
      Kind      : Tarlib.Entries.Entry_Kind;
      Link_Path : String;
      Metadata  : Tarlib.Entries.Metadata;
      Result    : out Tarlib.Errors.Status);
   --  Add a hard link or symbolic link entry.
   --  @param Archive Ready writer.
   --  @param Path Archive-relative USTAR path for the link entry.
   --  @param Kind Hard_Link or Symbolic_Link.
   --  @param Link_Path Link target encoded in USTAR or PAX metadata.
   --  Hard-link targets must be archive-relative; symbolic-link targets are
   --  preserved as supplied.
   --  @param Metadata Deterministic metadata to encode.
   --  @param Result Success or validation/output failure.

   procedure Add_Hard_Link
     (Archive   : in out Writer;
      Path      : String;
      Link_Path : String;
      Result    : out Tarlib.Errors.Status);
   --  Add a hard link entry with deterministic default metadata.

   procedure Add_Symbolic_Link
     (Archive   : in out Writer;
      Path      : String;
      Link_Path : String;
      Result    : out Tarlib.Errors.Status);
   --  Add a symbolic link entry with deterministic default metadata.

   procedure Add_Special
     (Archive  : in out Writer;
      Path     : String;
      Kind     : Tarlib.Entries.Entry_Kind;
      Device   : Tarlib.Entries.Device_Numbers;
      Metadata : Tarlib.Entries.Metadata;
      Result   : out Tarlib.Errors.Status);
   --  Add a character device, block device, or FIFO entry.

   procedure Add_Character_Device
     (Archive : in out Writer;
      Path    : String;
      Device  : Tarlib.Entries.Device_Numbers;
      Result  : out Tarlib.Errors.Status);
   --  Add a character device entry with deterministic default metadata.

   procedure Add_Block_Device
     (Archive : in out Writer;
      Path    : String;
      Device  : Tarlib.Entries.Device_Numbers;
      Result  : out Tarlib.Errors.Status);
   --  Add a block device entry with deterministic default metadata.

   procedure Add_FIFO
     (Archive : in out Writer;
      Path    : String;
      Result  : out Tarlib.Errors.Status);
   --  Add a FIFO entry with deterministic default metadata.

   procedure Add_Extended_Record
     (Archive : in out Writer;
      Keyword : String;
      Value   : String;
      Result  : out Tarlib.Errors.Status);
   --  Emit one local PAX extension record for the next entry.
   --  @param Archive Ready writer.
   --  @param Keyword Non-empty PAX key without '=' or embedded NUL.
   --  @param Value PAX value without embedded NUL.
   --  @param Result Success or validation/output failure.

   procedure Write
     (Archive : in out Writer;
      Data    : Ada.Streams.Stream_Element_Array;
      Result  : out Tarlib.Errors.Status);
   --  Append content bytes to the active data-bearing entry.
   --  @param Archive Writer in Writing_Entry for a data-bearing entry.
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
