with Interfaces;
with Tarlib.Errors;

package Tarlib.Entries
  with Pure
is
   --  Public entry metadata model for supported archive entries.

   type Entry_Kind is
     (Regular_File,
      Directory,
      Hard_Link,
      Symbolic_Link,
      Character_Device,
      Block_Device,
      FIFO,
      PAX_Extended_Header,
      PAX_Global_Header,
      GNU_Long_Name,
      GNU_Long_Link,
      GNU_Sparse,
      Volume_Label,
      Multi_Volume,
      Incremental_Dump);
   --  Archive entry kinds represented by the reader and internal header codec.
   --  Writer convenience APIs create regular files, directories, links,
   --  devices, and FIFOs; PAX/GNU metadata kinds are managed internally.
   --  Generic stream APIs can also represent data-bearing GNU multi-volume
   --  continuation and incremental dump directory entries.

   subtype File_Size is Tarlib.Byte_Count;
   --  Declared regular-file content size in bytes.

   subtype File_Mode is Interfaces.Unsigned_32 range 0 .. 8#7777#;
   --  POSIX permission mode encoded in the USTAR mode field.

   subtype Owner_Id is Interfaces.Unsigned_64;
   --  UID or GID value.

   subtype Device_Number is Interfaces.Unsigned_32 range 0 .. 8#7777777#;
   --  Device major or minor number encoded in USTAR device fields.

   subtype Timestamp is Interfaces.Integer_64;
   --  Timestamp seconds since the Unix epoch; PAX metadata may be negative.

   subtype Archive_Offset is Interfaces.Unsigned_64;
   --  Logical byte offset used by GNU multi-volume continuation metadata.

   Max_Metadata_Text_Length : constant := 256;
   --  Maximum PAX-backed textual metadata length retained by the API.

   type Metadata_Text is record
      Data   : String (1 .. Max_Metadata_Text_Length) :=
        [others => Character'Val (0)];
      Length : Natural range 0 .. Max_Metadata_Text_Length := 0;
   end record;
   --  Bounded textual metadata field used for owner/group names.

   Default_File_Mode : constant File_Mode := 8#0644#;
   --  Deterministic default mode for regular files.

   Default_Directory_Mode : constant File_Mode := 8#0755#;
   --  Deterministic default mode for directories.

   Default_Link_Mode : constant File_Mode := 8#0777#;
   --  Deterministic default mode for symbolic links.

   Default_Special_Mode : constant File_Mode := 8#0644#;
   --  Deterministic default mode for device and FIFO entries.

   Default_Owner : constant Owner_Id := 0;
   --  Deterministic UID and GID default.

   Default_Timestamp : constant Timestamp := 0;
   --  Deterministic modification time default.

   type Metadata is record
      Mode  : File_Mode := Default_File_Mode;
      UID   : Owner_Id := Default_Owner;
      GID   : Owner_Id := Default_Owner;
      MTime : Timestamp := Default_Timestamp;
      ATime : Timestamp := Default_Timestamp;
      CTime : Timestamp := Default_Timestamp;
      User_Name  : Metadata_Text;
      Group_Name : Metadata_Text;
   end record;
   --  Caller-supplied deterministic metadata.

   type Device_Numbers is record
      Major : Device_Number := 0;
      Minor : Device_Number := 0;
   end record;
   --  Device major/minor metadata for character and block device entries.

   No_Device : constant Device_Numbers := (Major => 0, Minor => 0);
   --  Canonical empty device metadata for non-device entries.

   type Sparse_Extent is record
      Offset : File_Size := 0;
      Length : File_Size := 0;
   end record;
   --  Logical sparse data extent. The archive stores the extent bytes
   --  consecutively while holes are represented by omitted zero ranges.

   type Sparse_Extent_Array is array (Positive range <>) of Sparse_Extent;

   function Default_Metadata (Kind : Entry_Kind) return Metadata;
   --  Return deterministic metadata defaults for Kind.
   --  @param Kind Entry kind whose defaults are requested.
   --  @return Metadata with canonical deterministic values.

   function Text (Value : Metadata_Text) return String;
   --  Return the stored textual metadata value.
   --  @param Value Bounded metadata field to read.
   --  @return Its text, without the padding the bound implies.

   procedure Set_Text
     (Value  : in out Metadata_Text;
      Text   : String;
      Result : out Tarlib.Errors.Status);
   --  Set a bounded textual metadata value, rejecting overlong or NUL text.
   --  @param Value Field to write.
   --  @param Text Replacement text.
   --  @param Result Ok, or why the text was refused: too long for the field, or
   --         carrying a NUL, which a tar header cannot represent.

end Tarlib.Entries;
