with Ada.Streams;

package Tarlib.Internal.Constants
  with Pure
is
   --  POSIX USTAR fixed sizes, offsets, and byte values.

   Block_Size : constant := 512;
   --  TAR block size in bytes.

   Name_Size : constant := 100;
   --  USTAR name field size in bytes.

   Prefix_Size : constant := 155;
   --  USTAR prefix field size in bytes.

   subtype Header_Block is Ada.Streams.Stream_Element_Array
     (1 .. Block_Size);
   --  One 512-byte TAR header or padding block.

   Zero_Block : constant Header_Block := [others => 0];
   --  Canonical zero-filled block used for padding and archive termination.

   Checksum_First : constant Ada.Streams.Stream_Element_Offset := 149;
   --  First one-based byte of the checksum field.

   Checksum_Last : constant Ada.Streams.Stream_Element_Offset := 156;
   --  Last one-based byte of the checksum field.
end Tarlib.Internal.Constants;
