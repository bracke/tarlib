with Tarlib.Entries;
with Tarlib.Errors;
with Tarlib.Internal.Constants;

package Tarlib.Internal.Headers
  with Pure
is
   --  POSIX USTAR-compatible header construction and parsing.

   procedure Build
     (Path     : String;
      Kind     : Tarlib.Entries.Entry_Kind;
      Size     : Tarlib.Byte_Count;
      Metadata : Tarlib.Entries.Metadata;
      Header   : out Tarlib.Internal.Constants.Header_Block;
      Result   : out Tarlib.Errors.Status);
   --  Build a complete 512-byte USTAR header.
   --  @param Path Validated archive-relative path candidate.
   --  @param Kind Header entry kind to encode.
   --  @param Size Declared content size; directories require zero.
   --  @param Metadata Caller-supplied deterministic metadata.
   --  @param Header Output header block.
   --  @param Result Success or validation/encoding failure.

   procedure Build
     (Path      : String;
      Kind      : Tarlib.Entries.Entry_Kind;
      Size      : Tarlib.Byte_Count;
      Metadata  : Tarlib.Entries.Metadata;
      Link_Path : String;
      Header    : out Tarlib.Internal.Constants.Header_Block;
      Result    : out Tarlib.Errors.Status);
   --  Build a complete 512-byte USTAR header with an optional link target.

   procedure Build
     (Path      : String;
      Kind      : Tarlib.Entries.Entry_Kind;
      Size      : Tarlib.Byte_Count;
      Metadata  : Tarlib.Entries.Metadata;
      Link_Path : String;
      Device    : Tarlib.Entries.Device_Numbers;
      Header    : out Tarlib.Internal.Constants.Header_Block;
      Result    : out Tarlib.Errors.Status);
   --  Build a complete 512-byte USTAR header.

   Max_Header_Sparse_Extents : constant := 4;
   --  Number of sparse extents stored directly in an old GNU header.

   type Header_Sparse_Extent is record
      Offset : Tarlib.Byte_Count := 0;
      Length : Tarlib.Byte_Count := 0;
   end record;

   type Header_Sparse_Extents is
     array (Positive range 1 .. Max_Header_Sparse_Extents)
       of Header_Sparse_Extent;

   type Parsed_Header is record
      Path_Text   : String (1 .. Tarlib.Internal.Constants.Name_Size
                                  + Tarlib.Internal.Constants.Prefix_Size + 1) :=
        [others => Character'Val (0)];
      Path_Length : Natural range 0 .. Tarlib.Internal.Constants.Name_Size
                                  + Tarlib.Internal.Constants.Prefix_Size + 1 := 0;
      Kind        : Tarlib.Entries.Entry_Kind := Tarlib.Entries.Regular_File;
      Size        : Tarlib.Byte_Count := 0;
      Link_Text   : String (1 .. Tarlib.Internal.Constants.Name_Size) :=
        [others => Character'Val (0)];
      Link_Length : Natural range 0 .. Tarlib.Internal.Constants.Name_Size := 0;
      Device      : Tarlib.Entries.Device_Numbers := Tarlib.Entries.No_Device;
      Multi_Volume_Offset : Tarlib.Entries.Archive_Offset := 0;
      Has_Multi_Volume_Offset : Boolean := False;
      Sparse_Extents : Header_Sparse_Extents;
      Sparse_Count   : Natural range 0 .. Max_Header_Sparse_Extents := 0;
      Sparse_Size    : Tarlib.Byte_Count := 0;
      Has_Sparse_Map : Boolean := False;
      Has_Sparse_Extension : Boolean := False;
      Metadata    : Tarlib.Entries.Metadata :=
        Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File);
   end record;
   --  Parsed USTAR header fields.

   procedure Parse
     (Header : Tarlib.Internal.Constants.Header_Block;
      Parsed : out Parsed_Header;
      Result : out Tarlib.Errors.Status);
   --  Parse and validate a complete 512-byte USTAR header.
   --  @param Header Header block to parse.
   --  @param Parsed Parsed fields when Result is Success.
   --  @param Result Success or validation failure.
end Tarlib.Internal.Headers;
