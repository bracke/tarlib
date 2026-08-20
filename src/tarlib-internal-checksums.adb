package body Tarlib.Internal.Checksums is
   use type Interfaces.Integer_64;
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

   function Compute_Signed
     (Header : Tarlib.Internal.Constants.Header_Block) return Interfaces.Integer_64
   is
      Sum  : Interfaces.Integer_64 := 0;
      Byte : Interfaces.Integer_64;
   begin
      for Index in Header'Range loop
         if Index in Tarlib.Internal.Constants.Checksum_First
           .. Tarlib.Internal.Constants.Checksum_Last
         then
            Sum := Sum + 32;
         else
            Byte := Interfaces.Integer_64 (Header (Index));
            if Byte >= 128 then
               Byte := Byte - 256;
            end if;
            Sum := Sum + Byte;
         end if;
      end loop;

      return Sum;
   end Compute_Signed;
end Tarlib.Internal.Checksums;
