with Ada.Streams;
with Tarlib.Entries;
with Tarlib.Errors;
with Tarlib.Inputs;

package Tarlib.Readers
  with Preelaborate
is
   --  Sequential blocking TAR archive reader.

   Max_Path_Length : constant := 1024;
   --  Maximum path length represented by USTAR or PAX path metadata.

   Max_Extended_Records : constant := 8;
   --  Maximum unknown local PAX records retained for an entry.

   Max_Sparse_Extents : constant := 32;
   --  Maximum sparse data extents reconstructed for an entry.

   Max_Incremental_Records : constant := 64;
   --  Maximum GNU incremental dump records parsed from one entry.

   Max_Vendor_Records : constant := 16;
   --  Maximum recognized vendor PAX records retained for typed access.

   type Reader_State is
     (Uninitialized, Ready, Reading_Entry, Finished, Failed);
   --  Explicit reader lifecycle state.

   type Reader is tagged limited private;
   --  Reader state. The reader does not own the input source.

   type Entry_Info is private;
   --  Parsed entry header metadata for the current archive entry.

   type Incremental_Listing is private;
   --  Parsed GNU incremental dump directory listing.

   procedure Initialize
     (Archive : in out Reader;
      Source  : aliased in out Tarlib.Inputs.Input_Source'Class;
      Result  : out Tarlib.Errors.Status);
   --  Attach a caller-owned input source and enter Ready.
   --  @param Archive Reader to initialize; must be Uninitialized.
   --  @param Source Source that must outlive Archive or any later calls.
   --  @param Result Success or Invalid_State.

   procedure Next_Entry
     (Archive   : in out Reader;
      Info      : out Entry_Info;
      Has_Entry : out Boolean;
      Result    : out Tarlib.Errors.Status);
   --  Advance to the next entry header.
   --  @param Archive Ready or Reading_Entry reader.
   --  @param Info Parsed metadata when Has_Entry is True.
   --  @param Has_Entry False when the archive terminator is reached.
   --  @param Result Success or validation/input failure.

   procedure Read
     (Archive : in out Reader;
      Data    : out Ada.Streams.Stream_Element_Array;
      Last    : out Ada.Streams.Stream_Element_Offset;
      Result  : out Tarlib.Errors.Status);
   --  Read content bytes from the active regular-file entry.
   --  @param Archive Reader in Reading_Entry for a regular file.
   --  @param Data Destination buffer.
   --  @param Last Last written index, or Data'First - 1 at end of entry.
   --  @param Result Success or input/state failure.

   procedure Skip_Entry
     (Archive : in out Reader;
      Result  : out Tarlib.Errors.Status);
   --  Skip the remaining content and padding for the active entry.
   --  @param Archive Reader in Reading_Entry.
   --  @param Result Success or input/state failure.

   procedure Read_Incremental_Dump
     (Archive : in out Reader;
      Listing : out Incremental_Listing;
      Result  : out Tarlib.Errors.Status);
   --  Read and parse the active GNU incremental dump entry payload.

   function State (Archive : Reader) return Reader_State;
   --  Return the current reader state.

   function At_End (Archive : Reader) return Boolean;
   --  Return True after the archive terminator has been reached cleanly.

   function Path (Info : Entry_Info) return String;
   --  Return the archive-relative path for Info.

   function Kind (Info : Entry_Info) return Tarlib.Entries.Entry_Kind;
   --  Return the entry kind for Info.

   function Size (Info : Entry_Info) return Tarlib.Byte_Count;
   --  Return the declared content size for Info.

   function Link_Path (Info : Entry_Info) return String;
   --  Return the link target for hard link and symbolic link entries.

   function Device (Info : Entry_Info) return Tarlib.Entries.Device_Numbers;
   --  Return device major/minor numbers for character and block devices.

   function Multi_Volume_Offset
     (Info : Entry_Info) return Tarlib.Entries.Archive_Offset;
   --  Return GNU multi-volume continuation offset metadata, or zero.

   function Metadata (Info : Entry_Info) return Tarlib.Entries.Metadata;
   --  Return deterministic metadata parsed from Info.

   function Extended_Record_Count (Info : Entry_Info) return Natural;
   --  Return the number of retained unknown local PAX records.

   function Extended_Key
     (Info  : Entry_Info;
      Index : Positive) return String;
   --  Return an unknown local PAX key by 1-based index, or "" out of range.

   function Extended_Value
     (Info  : Entry_Info;
      Index : Positive) return String;
   --  Return an unknown local PAX value by 1-based index, or "" out of range.

   function XAttr_Count (Info : Entry_Info) return Natural;
   --  Return the number of retained `SCHILY.xattr.*` PAX records.

   function XAttr_Name
     (Info  : Entry_Info;
      Index : Positive) return String;
   --  Return an xattr name without the `SCHILY.xattr.` prefix.

   function XAttr_Value
     (Info  : Entry_Info;
      Index : Positive) return String;
   --  Return an xattr value by 1-based index, or "" out of range.

   function ACL_Access (Info : Entry_Info) return String;
   --  Return retained `SCHILY.acl.access`, or "" when absent.

   function ACL_Default (Info : Entry_Info) return String;
   --  Return retained `SCHILY.acl.default`, or "" when absent.

   function File_Flags (Info : Entry_Info) return String;
   --  Return retained `LIBARCHIVE.fflags`, or "" when absent.

   function Incremental_Record_Count
     (Listing : Incremental_Listing) return Natural;
   --  Return parsed GNU incremental dump record count.

   function Incremental_Record_Path
     (Listing : Incremental_Listing;
      Index   : Positive) return String;
   --  Return an incremental record path by 1-based index, or "" out of range.

   function Incremental_Record_Is_Directory
     (Listing : Incremental_Listing;
      Index   : Positive) return Boolean;
   --  Return True for `Y` records and False for `N` records or out of range.

private
   type Input_Source_Access is access all Tarlib.Inputs.Input_Source'Class;

   type Extension_Texts is
     array (Positive range 1 .. Max_Extended_Records)
       of Tarlib.Entries.Metadata_Text;

   type Sparse_Extent is record
      Offset : Tarlib.Byte_Count := 0;
      Length : Tarlib.Byte_Count := 0;
   end record;

   type Sparse_Extents is
     array (Positive range 1 .. Max_Sparse_Extents) of Sparse_Extent;

   type Incremental_Record is record
      Is_Directory : Boolean := False;
      Path_Text    : String (1 .. Max_Path_Length) :=
        [others => Character'Val (0)];
      Path_Length  : Natural range 0 .. Max_Path_Length := 0;
   end record;

   type Incremental_Records is
     array (Positive range 1 .. Max_Incremental_Records)
       of Incremental_Record;

   type Incremental_Listing is record
      Record_Count : Natural range 0 .. Max_Incremental_Records := 0;
      Records      : Incremental_Records;
   end record;

   subtype Vendor_Text is Tarlib.Entries.Metadata_Text;
   type Vendor_Texts is
     array (Positive range 1 .. Max_Vendor_Records) of Vendor_Text;

   type Entry_Info is record
      Path_Text   : String (1 .. Max_Path_Length) := [others => Character'Val (0)];
      Path_Length : Natural range 0 .. Max_Path_Length := 0;
      Link_Text   : String (1 .. Max_Path_Length) := [others => Character'Val (0)];
      Link_Length : Natural range 0 .. Max_Path_Length := 0;
      Device_Info : Tarlib.Entries.Device_Numbers := Tarlib.Entries.No_Device;
      Volume_Offset : Tarlib.Entries.Archive_Offset := 0;
      Entry_Kind  : Tarlib.Entries.Entry_Kind := Tarlib.Entries.Regular_File;
      Entry_Size  : Tarlib.Byte_Count := 0;
      Entry_Meta  : Tarlib.Entries.Metadata :=
        Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File);
      Extension_Count  : Natural range 0 .. Max_Extended_Records := 0;
      Extension_Keys   : Extension_Texts;
      Extension_Values : Extension_Texts;
      XAttr_Count_Value : Natural range 0 .. Max_Vendor_Records := 0;
      XAttr_Names       : Vendor_Texts;
      XAttr_Values      : Vendor_Texts;
      ACL_Access_Value  : Vendor_Text;
      Has_ACL_Access    : Boolean := False;
      ACL_Default_Value : Vendor_Text;
      Has_ACL_Default   : Boolean := False;
      File_Flags_Value  : Vendor_Text;
      Has_File_Flags    : Boolean := False;
   end record;

   type Reader is tagged limited record
      Current_State    : Reader_State := Uninitialized;
      Source           : Input_Source_Access := null;
      Active_Kind      : Tarlib.Entries.Entry_Kind := Tarlib.Entries.Regular_File;
      Remaining_Size   : Tarlib.Byte_Count := 0;
      Remaining_Padding : Natural := 0;
      Pending_Path      : String (1 .. Max_Path_Length) :=
        [others => Character'Val (0)];
      Pending_Path_Length : Natural range 0 .. Max_Path_Length := 0;
      Pending_Link_Path : String (1 .. Max_Path_Length) :=
        [others => Character'Val (0)];
      Pending_Link_Path_Length : Natural range 0 .. Max_Path_Length := 0;
      Pending_Size       : Tarlib.Byte_Count := 0;
      Has_Pending_Size   : Boolean := False;
      Pending_MTime      : Tarlib.Entries.Timestamp := 0;
      Has_Pending_MTime  : Boolean := False;
      Pending_ATime      : Tarlib.Entries.Timestamp := 0;
      Has_Pending_ATime  : Boolean := False;
      Pending_CTime      : Tarlib.Entries.Timestamp := 0;
      Has_Pending_CTime  : Boolean := False;
      Pending_UID        : Tarlib.Entries.Owner_Id := 0;
      Has_Pending_UID    : Boolean := False;
      Pending_GID        : Tarlib.Entries.Owner_Id := 0;
      Has_Pending_GID    : Boolean := False;
      Pending_User_Name  : Tarlib.Entries.Metadata_Text;
      Has_Pending_User_Name : Boolean := False;
      Pending_Group_Name : Tarlib.Entries.Metadata_Text;
      Has_Pending_Group_Name : Boolean := False;
      Pending_Extension_Count  : Natural range 0 .. Max_Extended_Records := 0;
      Pending_Extension_Keys   : Extension_Texts;
      Pending_Extension_Values : Extension_Texts;
      Pending_Device_Major : Tarlib.Entries.Device_Number := 0;
      Has_Pending_Device_Major : Boolean := False;
      Pending_Device_Minor : Tarlib.Entries.Device_Number := 0;
      Has_Pending_Device_Minor : Boolean := False;
      Pending_Sparse_Extents : Sparse_Extents;
      Pending_Sparse_Count   : Natural range 0 .. Max_Sparse_Extents := 0;
      Pending_Sparse_Size    : Tarlib.Byte_Count := 0;
      Has_Pending_Sparse_Size : Boolean := False;
      Has_Pending_Sparse_Map  : Boolean := False;
      Pending_Sparse_Offset : Tarlib.Byte_Count := 0;
      Has_Pending_Sparse_Offset : Boolean := False;
      Pending_Volume_Offset : Tarlib.Entries.Archive_Offset := 0;
      Has_Pending_Volume_Offset : Boolean := False;
      Pending_XAttr_Count : Natural range 0 .. Max_Vendor_Records := 0;
      Pending_XAttr_Names  : Vendor_Texts;
      Pending_XAttr_Values : Vendor_Texts;
      Pending_ACL_Access   : Vendor_Text;
      Has_Pending_ACL_Access : Boolean := False;
      Pending_ACL_Default  : Vendor_Text;
      Has_Pending_ACL_Default : Boolean := False;
      Pending_File_Flags   : Vendor_Text;
      Has_Pending_File_Flags : Boolean := False;
      Has_Pending_Extension : Boolean := False;
      Global_MTime       : Tarlib.Entries.Timestamp := 0;
      Has_Global_MTime   : Boolean := False;
      Global_ATime       : Tarlib.Entries.Timestamp := 0;
      Has_Global_ATime   : Boolean := False;
      Global_CTime       : Tarlib.Entries.Timestamp := 0;
      Has_Global_CTime   : Boolean := False;
      Global_UID         : Tarlib.Entries.Owner_Id := 0;
      Has_Global_UID     : Boolean := False;
      Global_GID         : Tarlib.Entries.Owner_Id := 0;
      Has_Global_GID     : Boolean := False;
      Global_User_Name   : Tarlib.Entries.Metadata_Text;
      Has_Global_User_Name : Boolean := False;
      Global_Group_Name  : Tarlib.Entries.Metadata_Text;
      Has_Global_Group_Name : Boolean := False;
      Active_Physical_Size : Tarlib.Byte_Count := 0;
      Active_Logical_Offset : Tarlib.Byte_Count := 0;
      Active_Sparse_Extents : Sparse_Extents;
      Active_Sparse_Count   : Natural range 0 .. Max_Sparse_Extents := 0;
      Active_Sparse_Index   : Natural range 1 .. Max_Sparse_Extents := 1;
   end record;
end Tarlib.Readers;
