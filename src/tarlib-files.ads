with Ada.Streams;
with Ada.Streams.Stream_IO;
with Tarlib.Errors;
with Tarlib.Inputs;
with Tarlib.Outputs;
with Tarlib.Readers;
with Tarlib.Writers;

package Tarlib.Files is
   --  Filesystem-backed stream adapters and portable pack/extract helpers.

   type File_Input_Source is limited new Tarlib.Inputs.Input_Source with private;

   procedure Open_Read
     (Source : in out File_Input_Source;
      Path   : String;
      Result : out Tarlib.Errors.Status);
   --  Open an archive file for reading through the stream interface a Reader
   --  takes, so a caller reading from a file need not write an adapter.
   --  @param Source Source to open.
   --  @param Path Archive file to read.
   --  @param Result Ok, or why it could not be opened.

   procedure Close
     (Source : in out File_Input_Source;
      Result : out Tarlib.Errors.Status);
   --  @param Source Source to close.
   --  @param Result Ok, or why the file could not be closed.

   overriding procedure Read
     (Source : in out File_Input_Source;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Tarlib.Errors.Status);
   --  @param Source Source to read from.
   --  @param Data Buffer to fill.
   --  @param Last Last element written; below Data'First at end of file.
   --  @param Result Ok, or why the read failed.

   type File_Output_Sink is limited new Tarlib.Outputs.Output_Sink with private;

   procedure Create_Write
     (Sink   : in out File_Output_Sink;
      Path   : String;
      Result : out Tarlib.Errors.Status);
   --  Create an archive file for writing through the stream interface a Writer
   --  takes.
   --  @param Sink Sink to create.
   --  @param Path Archive file to write; an existing file is replaced.
   --  @param Result Ok, or why it could not be created.

   procedure Close
     (Sink   : in out File_Output_Sink;
      Result : out Tarlib.Errors.Status);
   --  @param Sink Sink to close.
   --  @param Result Ok, or why the file could not be closed.

   overriding procedure Write
     (Sink   : in out File_Output_Sink;
      Data   : Ada.Streams.Stream_Element_Array;
      Result : out Tarlib.Errors.Status);
   --  @param Sink Sink to write to.
   --  @param Data Bytes to write.
   --  @param Result Ok, or why the write failed.

   procedure Add_File
     (Archive         : in out Tarlib.Writers.Writer;
      Filesystem_Path : String;
      Archive_Path    : String;
      Result          : out Tarlib.Errors.Status);
   --  Add one regular filesystem file to Archive.
   --  @param Archive Writer to add to; it must be Ready.
   --  @param Filesystem_Path File to read the bytes from.
   --  @param Archive_Path Name the entry carries in the archive, which need
   --         not resemble the filesystem path.
   --  @param Result Ok, or why the entry was not written.

   procedure Add_Tree
     (Archive         : in out Tarlib.Writers.Writer;
      Filesystem_Path : String;
      Archive_Path    : String;
      Result          : out Tarlib.Errors.Status);
   --  Add a filesystem file or directory tree to Archive.
   --  @param Archive Writer to add to.
   --  @param Filesystem_Path File or directory to walk.
   --  @param Archive_Path Name the tree is rooted under in the archive.
   --  @param Result Ok, or why a member was not written.

   procedure Extract_All
     (Archive               : in out Tarlib.Readers.Reader;
      Destination_Directory : String;
      Result                : out Tarlib.Errors.Status);
   --  Extract regular files and directories below Destination_Directory.
   --  Link, device, and FIFO entries are reported as Invalid_Entry_Kind.
   --  @param Archive Reader positioned at the start of the archive.
   --  @param Destination_Directory Directory to extract below; entries cannot
   --         escape it, whatever paths the archive carries.
   --  @param Result Ok, or why extraction stopped.

   type Unsupported_Entry_Action is (Reject_Unsupported, Skip_Unsupported);
   type Device_Number_Layout is
     (Native_Device_Layout,
      Linux_Device_Layout,
      BSD_Device_Layout,
      Solaris_Device_Layout);

   type Extraction_Options is record
      Unsupported_Entries : Unsupported_Entry_Action := Reject_Unsupported;
      Apply_Permissions   : Boolean := False;
      Apply_Timestamps    : Boolean := False;
      Apply_Ownership     : Boolean := False;
      Create_Special_Entries : Boolean := False;
      Extract_GNU_Metadata : Boolean := False;
      Device_Layout : Device_Number_Layout := Native_Device_Layout;
      Apply_Extended_Attributes : Boolean := False;
      Apply_ACLs : Boolean := False;
      Apply_File_Flags : Boolean := False;
      Apply_Native_ACLs : Boolean := False;
      Apply_Native_File_Flags : Boolean := False;
   end record;

   procedure Extract_All
     (Archive               : in out Tarlib.Readers.Reader;
      Destination_Directory : String;
      Options               : Extraction_Options;
      Result                : out Tarlib.Errors.Status);
   --  Extract entries below Destination_Directory with caller-selected policy.
   --  POSIX options apply mode, timestamps, ownership, and special filesystem
   --  nodes where the platform and process privileges support them. GNU
   --  metadata extraction materializes multi-volume payloads, incremental
   --  listings, and volume labels instead of treating them as unsupported.
   --  @param Archive Reader positioned at the start of the archive.
   --  @param Destination_Directory Directory to extract below.
   --  @param Options What to allow and what to apply. Everything beyond
   --         regular files and directories is off by default, because
   --         restoring ownership or a device node is a decision, not a detail.
   --  @param Result Ok, or why extraction stopped.

   procedure Reassemble_Multi_Volume_File
     (Volume_Path_List : String;
      Output_Path      : String;
      Result           : out Tarlib.Errors.Status);
   --  Reassemble one logical regular file split across archive volumes.
   --  Each archive must contain the initial regular-file entry or a GNU
   --  multi-volume continuation entry for the same logical payload. Volume
   --  paths are supplied one per line in processing order.
   --  @param Volume_Path_List Archive paths, one per line, in the order the
   --         volumes were written.
   --  @param Output_Path File to write the reassembled payload to.
   --  @param Result Ok, or why the volumes did not form one payload -- a
   --         missing continuation, or an offset that does not follow.

private
   type File_Input_Source is limited new Tarlib.Inputs.Input_Source with record
      File : Ada.Streams.Stream_IO.File_Type;
   end record;

   type File_Output_Sink is limited new Tarlib.Outputs.Output_Sink with record
      File : Ada.Streams.Stream_IO.File_Type;
   end record;
end Tarlib.Files;
