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

   procedure Close
     (Source : in out File_Input_Source;
      Result : out Tarlib.Errors.Status);

   overriding procedure Read
     (Source : in out File_Input_Source;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Tarlib.Errors.Status);

   type File_Output_Sink is limited new Tarlib.Outputs.Output_Sink with private;

   procedure Create_Write
     (Sink   : in out File_Output_Sink;
      Path   : String;
      Result : out Tarlib.Errors.Status);

   procedure Close
     (Sink   : in out File_Output_Sink;
      Result : out Tarlib.Errors.Status);

   overriding procedure Write
     (Sink   : in out File_Output_Sink;
      Data   : Ada.Streams.Stream_Element_Array;
      Result : out Tarlib.Errors.Status);

   procedure Add_File
     (Archive         : in out Tarlib.Writers.Writer;
      Filesystem_Path : String;
      Archive_Path    : String;
      Result          : out Tarlib.Errors.Status);
   --  Add one regular filesystem file to Archive.

   procedure Add_Tree
     (Archive         : in out Tarlib.Writers.Writer;
      Filesystem_Path : String;
      Archive_Path    : String;
      Result          : out Tarlib.Errors.Status);
   --  Add a filesystem file or directory tree to Archive.

   procedure Extract_All
     (Archive               : in out Tarlib.Readers.Reader;
      Destination_Directory : String;
      Result                : out Tarlib.Errors.Status);
   --  Extract regular files and directories below Destination_Directory.
   --  Link, device, and FIFO entries are reported as Invalid_Entry_Kind.

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

   procedure Reassemble_Multi_Volume_File
     (Volume_Path_List : String;
      Output_Path      : String;
      Result           : out Tarlib.Errors.Status);
   --  Reassemble one logical regular file split across archive volumes.
   --  Each archive must contain the initial regular-file entry or a GNU
   --  multi-volume continuation entry for the same logical payload. Volume
   --  paths are supplied one per line in processing order.

private
   type File_Input_Source is limited new Tarlib.Inputs.Input_Source with record
      File : Ada.Streams.Stream_IO.File_Type;
   end record;

   type File_Output_Sink is limited new Tarlib.Outputs.Output_Sink with record
      File : Ada.Streams.Stream_IO.File_Type;
   end record;
end Tarlib.Files;
