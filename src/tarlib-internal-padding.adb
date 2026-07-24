with Interfaces;

package body Tarlib.Internal.Padding is
   use type Interfaces.Unsigned_64;

   function Padding_Length (Size : Tarlib.Byte_Count) return Natural is
      Remainder : constant Interfaces.Unsigned_64 := Size mod 512;
   begin
      if Remainder = 0 then
         return 0;
      end if;

      return Natural (512 - Remainder);
   end Padding_Length;
end Tarlib.Internal.Padding;
