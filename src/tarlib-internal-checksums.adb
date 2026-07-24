with Ada.Streams;

package body Tarlib.Internal.Checksums is
   use type Ada.Streams.Stream_Element_Offset;
   use type Interfaces.Unsigned_64;

   function Compute
     (Header : Tarlib.Internal.Constants.Header_Block) return Checksum_Value
   is
      Sum : Checksum_Value := 0;
   begin
      for Index in Header'Range loop
         if Index in Tarlib.Internal.Constants.Checksum_First
           .. Tarlib.Internal.Constants.Checksum_Last
         then
            Sum := Sum + Checksum_Value (32);
         else
            Sum := Sum + Checksum_Value (Header (Index));
         end if;
      end loop;

      return Sum;
   end Compute;
end Tarlib.Internal.Checksums;
