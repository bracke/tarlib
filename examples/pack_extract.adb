with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Text_IO;

with Tarlib.Errors;
with Tarlib.Files;
with Tarlib.Readers;
with Tarlib.Writers;

procedure Pack_Extract is
   use type Ada.Streams.Stream_Element_Offset;
   use type Tarlib.Errors.Status_Code;

   procedure Require_Success
     (Result : Tarlib.Errors.Status;
      Step   : String) is
   begin
      if Result.Code /= Tarlib.Errors.Success then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error, Step & " failed");
         raise Program_Error;
      end if;
   end Require_Success;

   function To_Bytes (Text : String) return Ada.Streams.Stream_Element_Array is
      Data : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Text'Length));
   begin
      for Offset in 0 .. Text'Length - 1 loop
         Data
           (Data'First + Ada.Streams.Stream_Element_Offset (Offset)) :=
           Ada.Streams.Stream_Element
             (Character'Pos (Text (Text'First + Offset)));
      end loop;

      return Data;
   end To_Bytes;

   procedure Write_File (Path : String; Text : String) is
      File : Ada.Streams.Stream_IO.File_Type;
   begin
      Ada.Streams.Stream_IO.Create
        (File, Ada.Streams.Stream_IO.Out_File, Path);
      Ada.Streams.Stream_IO.Write (File, To_Bytes (Text));
      Ada.Streams.Stream_IO.Close (File);
   end Write_File;

   Result : Tarlib.Errors.Status;
   Sink   : aliased Tarlib.Files.File_Output_Sink;
   Source : aliased Tarlib.Files.File_Input_Source;
   Writer : Tarlib.Writers.Writer;
   Reader : Tarlib.Readers.Reader;
begin
   Ada.Directories.Create_Path ("example-input/subdir");
   Write_File ("example-input/subdir/file.txt", "packed by tarlib" & Character'Val (10));

   Tarlib.Files.Create_Write (Sink, "tree.tar", Result);
   Require_Success (Result, "create archive");
   Tarlib.Writers.Initialize (Writer, Sink, Result);
   Require_Success (Result, "initialize writer");
   Tarlib.Files.Add_Tree (Writer, "example-input", "example-input", Result);
   Require_Success (Result, "pack tree");
   Tarlib.Writers.Finish (Writer, Result);
   Require_Success (Result, "finish archive");
   Tarlib.Files.Close (Sink, Result);
   Require_Success (Result, "close archive");

   Tarlib.Files.Open_Read (Source, "tree.tar", Result);
   Require_Success (Result, "open archive");
   Tarlib.Readers.Initialize (Reader, Source, Result);
   Require_Success (Result, "initialize reader");
   Tarlib.Files.Extract_All (Reader, "example-output", Result);
   Require_Success (Result, "extract archive");
   Tarlib.Files.Close (Source, Result);
   Require_Success (Result, "close input");

   Ada.Text_IO.Put_Line ("packed tree.tar and extracted to example-output");
end Pack_Extract;
