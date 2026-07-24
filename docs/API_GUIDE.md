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

## Lifecycle Rules

- `Initialize` must be called once before other reader/writer operations.
- A writer must be `Ready` before starting an entry.
- A writer entry must receive exactly its declared physical payload length.
- `End_Entry` emits padding after exact completion.
- `Finish` emits the two zero archive terminator blocks.
- A malformed archive or I/O failure moves a reader to `Failed`.
- An output failure moves a writer to `Failed`.
