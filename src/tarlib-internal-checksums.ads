with Interfaces;
with Tarlib.Internal.Constants;

package Tarlib.Internal.Checksums
  with Pure
is
   --  POSIX TAR checksum calculation.

   subtype Checksum_Value is Interfaces.Unsigned_64;
   --  Sum of unsigned header bytes.

   function Compute
     (Header : Tarlib.Internal.Constants.Header_Block) return Checksum_Value;
   --  Compute checksum while treating the checksum field as spaces.
   --  @param Header Header block to inspect.
   --  @return Standard TAR unsigned byte checksum.
end Tarlib.Internal.Checksums;
