with Interfaces;

package Tarlib
  with Pure
is
   --  Root package for the deterministic POSIX tar read/write library.

   Version : constant String := "0.1.0";
   --  Semantic version of this library release.

   subtype Byte_Count is Interfaces.Unsigned_64;
   --  Count of archive content bytes.

   USTAR_Size_Max : constant Byte_Count := 8#77777777777#;
   --  Largest content byte count representable by the USTAR size field.

   USTAR_Owner_Max : constant Interfaces.Unsigned_64 := 8#7777777#;
   --  Largest UID, GID, or device number representable by USTAR fields.

   USTAR_Timestamp_Max : constant Byte_Count := USTAR_Size_Max;
   --  Largest modification time representable by the USTAR mtime field.

   Max_PAX_Data : constant := 65_536;
   --  Maximum PAX extended-header payload accepted or emitted by stream APIs.

   subtype Octal_Field_Value is Interfaces.Unsigned_64;
   --  Unsigned scalar used by internal octal field encoders.
end Tarlib;
