with Interfaces;
with Tarlib;

package Tarlib.Entries
  with Pure
is
   --  Public entry metadata model for supported archive entries.

   type Entry_Kind is (Regular_File, Directory);
   --  Supported POSIX USTAR entry kinds.

   subtype File_Size is Tarlib.Byte_Count;
   --  Declared regular-file content size in bytes.

   subtype File_Mode is Interfaces.Unsigned_32 range 0 .. 8#7777#;
   --  POSIX permission mode encoded in the USTAR mode field.

   subtype Owner_Id is Interfaces.Unsigned_32 range 0 .. 8#7777777#;
   --  UID or GID value encoded in the USTAR owner fields.

   subtype Timestamp is Tarlib.Byte_Count;
   --  Modification time as seconds since the Unix epoch.

   Default_File_Mode : constant File_Mode := 8#0644#;
   --  Deterministic default mode for regular files.

   Default_Directory_Mode : constant File_Mode := 8#0755#;
   --  Deterministic default mode for directories.

   Default_Owner : constant Owner_Id := 0;
   --  Deterministic UID and GID default.

   Default_Timestamp : constant Timestamp := 0;
   --  Deterministic modification time default.

   type Metadata is record
      Mode  : File_Mode := Default_File_Mode;
      UID   : Owner_Id := Default_Owner;
      GID   : Owner_Id := Default_Owner;
      MTime : Timestamp := Default_Timestamp;
   end record;
   --  Caller-supplied deterministic metadata. User and group names are
   --  intentionally empty in this initial API.

   function Default_Metadata (Kind : Entry_Kind) return Metadata;
   --  Return deterministic metadata defaults for Kind.
   --  @param Kind Entry kind whose defaults are requested.
   --  @return Metadata with canonical deterministic values.
end Tarlib.Entries;
