package Tarlib.Internal.Padding
  with Pure
is
   --  TAR block padding arithmetic.

   function Padding_Length (Size : Tarlib.Byte_Count) return Natural;
   --  Return bytes needed to align Size to the next 512-byte boundary.
   --  @param Size Content size in bytes.
   --  @return Value in 0 .. 511.
end Tarlib.Internal.Padding;
