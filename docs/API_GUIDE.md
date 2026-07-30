# tarlib API Guide

This guide covers the public API surfaces most users need:

- `Tarlib.Writers` for sequential archive creation.
- `Tarlib.Readers` for sequential archive reading.
- `Tarlib.Files` for filesystem-backed streams, packing, extraction, and
  multi-volume reassembly.

All operations report failures through `Tarlib.Errors.Status`. Check
`Result.Code` after each call. A failed reader or writer enters a terminal
`Failed` state.

## Writing Archives

A writer is initialized with a caller-owned output sink. For files, call
`Begin_File`, write exactly the declared number of bytes, then call
`End_Entry`. Finish the archive with `Finish`.

```ada
Sink   : aliased Tarlib.Files.File_Output_Sink;
Writer : Tarlib.Writers.Writer;
Result : Tarlib.Errors.Status;
Data   : constant Ada.Streams.Stream_Element_Array :=
  [Character'Pos ('h'), Character'Pos ('i')];
begin
   Tarlib.Files.Create_Write (Sink, "sample.tar", Result);
   Tarlib.Writers.Initialize (Writer, Sink, Result);
   Tarlib.Writers.Begin_File (Writer, "hello.txt", 2, Result);
   Tarlib.Writers.Write (Writer, Data, Result);
   Tarlib.Writers.End_Entry (Writer, Result);
   Tarlib.Writers.Finish (Writer, Result);
   Tarlib.Files.Close (Sink, Result);
end;
```

Use `Add_Directory`, `Add_Hard_Link`, `Add_Symbolic_Link`,
`Add_Character_Device`, `Add_Block_Device`, and `Add_FIFO` for entries that do
not carry regular file data.

For sparse files, call `Begin_Sparse_File` with logical extents and then write
only the concatenated data bytes for those extents. Holes are represented by the
sparse metadata, not by zero bytes in the physical payload.

## Reading Archives

A reader is initialized with a caller-owned input source. Call `Next_Entry` in a
loop. For regular files, call `Read` until it returns no bytes. For entries you
do not need, call `Skip_Entry`.

```ada
Source    : aliased Tarlib.Files.File_Input_Source;
Reader    : Tarlib.Readers.Reader;
Info      : Tarlib.Readers.Entry_Info;
Result    : Tarlib.Errors.Status;
Has_Entry : Boolean;
begin
   Tarlib.Files.Open_Read (Source, "sample.tar", Result);
   Tarlib.Readers.Initialize (Reader, Source, Result);

   loop
      Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
      exit when Result.Code /= Tarlib.Errors.Success or else not Has_Entry;
      --  Inspect Tarlib.Readers.Path/Kind/Size/Metadata here.
      Tarlib.Readers.Skip_Entry (Reader, Result);
      exit when Result.Code /= Tarlib.Errors.Success;
   end loop;

   Tarlib.Files.Close (Source, Result);
end;
```

`Next_Entry` automatically skips unread data from the previous entry before
reading the next header.

## Filesystem Helpers

`Tarlib.Files.Add_File` adds one regular file. `Tarlib.Files.Add_Tree`
recursively packs ordinary files and directories. `Tarlib.Files.Extract_All`
extracts archive entries below a destination directory.

The simple `Extract_All` overload extracts regular files and directories and
rejects links, devices, and FIFOs. Use `Extraction_Options` when you want to
allow links, special nodes, timestamps, ownership, GNU metadata, xattrs, ACLs,
or file flags.

## Multi-Volume Reassembly

`Tarlib.Files.Reassemble_Multi_Volume_File` accepts a newline-separated list of
archive paths. The first archive must contain the initial regular file entry and
later archives must contain GNU multi-volume continuation entries with matching
offset metadata.

## Entry Metadata

`Entry_Info` carries what the header and any PAX or GNU records said about the
entry the reader is positioned on. `Link_Path` gives the target of a hard or
symbolic link. `Multi_Volume_Offset` gives the logical offset a GNU
continuation entry resumes at, which is what
`Reassemble_Multi_Volume_File` matches on.

A sparse entry reports the size it would occupy if written out in full through
`Sparse_Logical_Size`, against the `Sparse_Physical_Size` actually stored. The
extents are read by index, one-based:

```ada
for Index in 1 .. Tarlib.Readers.Sparse_Extent_Count (Info) loop
   Offset := Tarlib.Readers.Sparse_Extent_Offset (Info, Index);
   Length := Tarlib.Readers.Sparse_Extent_Length (Info, Index);
end loop;
```

Holes are reconstructed as zero bytes while reading, so a caller that does not
care about the extents does not have to look at them.

## Vendor Metadata

Extended attributes, ACL text and BSD file flags are read from the entry when
the archive carried them:

```ada
for Index in 1 .. Tarlib.Readers.XAttr_Count (Info) loop
   Name  := Tarlib.Readers.XAttr_Name (Info, Index);   --  without SCHILY.xattr.
   Value := Tarlib.Readers.XAttr_Value (Info, Index);
end loop;
```

`ACL_Access` and `ACL_Default` return the ACL text as stored, and `File_Flags`
the flags string. None of them are applied to the filesystem unless
`Extraction_Options` asks for it.

## PAX Records and GNU Incremental Dumps

Unknown local PAX records are retained rather than discarded, up to a bounded
count: `Extended_Record_Count`, `Extended_Key` and `Extended_Value` read them by
index. A writer injects its own with `Add_Extended_Record`.

`Read_Incremental_Dump` reads a GNU incremental dump entry into an
`Incremental_Listing`, whose entries are read by index through
`Incremental_Record_Count`, `Incremental_Record_Path` and
`Incremental_Record_Is_Directory`.

## Writing Entries Directly

`Tarlib.Files` is the convenient layer; the writer underneath it takes entries
one at a time. `Begin_Entry` emits a data or directory header and enters
`Writing_Entry`; `Add_Link` emits a hard or symbolic link; `Add_Special` emits a
device node or FIFO. `Default_Metadata` gives the fixed defaults for an entry
kind, which is what keeps an archive reproducible -- nothing is taken from the
clock or the environment unless the caller puts it there. `Metadata_Text` fields
are set with `Set_Text` and read with `Text`.

## Status and State

`Is_Success` is the one predicate over `Status`; the rest of `Tarlib.Errors`
names why something failed. `State` reports the writer's state and `At_End`
reports whether the reader has reached the archive terminator, which is how a
read loop ends without guessing.

## Lifecycle Rules

- `Initialize` must be called once before other reader/writer operations.
- A writer must be `Ready` before starting an entry.
- A writer entry must receive exactly its declared physical payload length.
- `End_Entry` emits padding after exact completion.
- `Finish` emits the two zero archive terminator blocks.
- A malformed archive or I/O failure moves a reader to `Failed`.
- An output failure moves a writer to `Failed`.
