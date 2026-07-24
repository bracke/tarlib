with Interfaces;

package Tarlib
  with Pure
is
   --  Root package for the deterministic write-only POSIX USTAR library.

   Version : constant String := "0.1.0";
   --  Semantic version of this library release.

   subtype Byte_Count is Interfaces.Unsigned_64
     range 0 .. 8#77777777777#;
   --  Count of archive content bytes representable by the supported USTAR
   --  size field.

   subtype Octal_Field_Value is Interfaces.Unsigned_64;
   --  Unsigned scalar used by internal octal field encoders.
end Tarlib;
