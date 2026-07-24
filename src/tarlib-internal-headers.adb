with Ada.Streams;
with Interfaces;
with Tarlib.Errors;
with Tarlib.Internal.Checksums;
with Tarlib.Internal.Fields;
with Tarlib.Internal.Paths;

package body Tarlib.Internal.Headers is
   use type Ada.Streams.Stream_Element_Offset;
   use type Interfaces.Unsigned_64;
   use type Tarlib.Entries.Entry_Kind;
   use type Tarlib.Errors.Status_Code;

   procedure Put_Bytes
     (Header : in out Tarlib.Internal.Constants.Header_Block;
      First  : Ada.Streams.Stream_Element_Offset;
      Text   : String;
      Result : out Tarlib.Errors.Status)
   is
      Last : constant Ada.Streams.Stream_Element_Offset :=
        First + Ada.Streams.Stream_Element_Offset (Text'Length) - 1;
   begin
      Tarlib.Internal.Fields.Put_String (Header (First .. Last), Text, Result);
   end Put_Bytes;

   procedure Build
     (Path     : String;
      Kind     : Tarlib.Entries.Entry_Kind;
      Size     : Tarlib.Byte_Count;
      Metadata : Tarlib.Entries.Metadata;
      Header   : out Tarlib.Internal.Constants.Header_Block;
      Result   : out Tarlib.Errors.Status)
   is
      Split    : constant Tarlib.Internal.Paths.Path_Split :=
        Tarlib.Internal.Paths.Split (Path);
      Checksum : Tarlib.Internal.Checksums.Checksum_Value;
   begin
      Header := [others => 0];

      if Split.Status.Code /= Tarlib.Errors.Success then
         Result := Split.Status;
         return;
      end if;

      if Kind = Tarlib.Entries.Directory and then Size /= 0 then
         Result := (Code => Tarlib.Errors.Invalid_Size);
         return;
      end if;

      Tarlib.Internal.Fields.Put_String
        (Header (1 .. 100), Path (Split.Name_First .. Split.Name_Last), Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Tarlib.Internal.Fields.Put_Octal
        (Header (101 .. 108), Interfaces.Unsigned_64 (Metadata.Mode),
         Tarlib.Internal.Fields.NUL_Terminated, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Tarlib.Internal.Fields.Put_Octal
        (Header (109 .. 116), Interfaces.Unsigned_64 (Metadata.UID),
         Tarlib.Internal.Fields.NUL_Terminated, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Tarlib.Internal.Fields.Put_Octal
        (Header (117 .. 124), Interfaces.Unsigned_64 (Metadata.GID),
         Tarlib.Internal.Fields.NUL_Terminated, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Tarlib.Internal.Fields.Put_Octal
        (Header (125 .. 136), Interfaces.Unsigned_64 (Size),
         Tarlib.Internal.Fields.NUL_Terminated, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Tarlib.Internal.Fields.Put_Octal
        (Header (137 .. 148), Interfaces.Unsigned_64 (Metadata.MTime),
         Tarlib.Internal.Fields.NUL_Terminated, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Header (149 .. 156) := [others => 32];
      Header (157) :=
        (case Kind is
            when Tarlib.Entries.Regular_File => Character'Pos ('0'),
            when Tarlib.Entries.Directory    => Character'Pos ('5'));
      Header (158 .. 257) := [others => 0];
      Put_Bytes (Header, 258, "ustar", Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;
      Header (263) := 0;
      Header (264) := Character'Pos ('0');
      Header (265) := Character'Pos ('0');
      Header (266 .. 329) := [others => 0];

      Tarlib.Internal.Fields.Put_Octal
        (Header (330 .. 337), 0, Tarlib.Internal.Fields.NUL_Terminated, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Tarlib.Internal.Fields.Put_Octal
        (Header (338 .. 345), 0, Tarlib.Internal.Fields.NUL_Terminated, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      if Split.Prefix_Length > 0 then
         Tarlib.Internal.Fields.Put_String
           (Header (346 .. 500),
            Path (Split.Prefix_First .. Split.Prefix_Last), Result);
         if Result.Code /= Tarlib.Errors.Success then
            return;
         end if;
      end if;

      Checksum := Tarlib.Internal.Checksums.Compute (Header);
      Tarlib.Internal.Fields.Put_Octal
        (Header (149 .. 156), Checksum,
         Tarlib.Internal.Fields.Checksum_Terminated, Result);
   end Build;
end Tarlib.Internal.Headers;
