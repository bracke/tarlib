with Tarlib;
with Tarlib.Entries;
with Tarlib.Errors;
with Tarlib.Internal.Constants;

package Tarlib.Internal.Headers
  with Pure
is
   --  POSIX USTAR header construction.

   procedure Build
     (Path     : String;
      Kind     : Tarlib.Entries.Entry_Kind;
      Size     : Tarlib.Byte_Count;
      Metadata : Tarlib.Entries.Metadata;
      Header   : out Tarlib.Internal.Constants.Header_Block;
      Result   : out Tarlib.Errors.Status);
   --  Build a complete 512-byte USTAR header.
   --  @param Path Validated archive-relative path candidate.
   --  @param Kind Supported entry kind.
   --  @param Size Declared content size; directories require zero.
   --  @param Metadata Caller-supplied deterministic metadata.
   --  @param Header Output header block.
   --  @param Result Success or validation/encoding failure.
end Tarlib.Internal.Headers;
