with Ada.Streams;
with Ada.Text_IO;

with Tarlib.Errors;
with Tarlib.Files;
with Tarlib.Writers;

procedure Write_Archive is
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

   Sink    : aliased Tarlib.Files.File_Output_Sink;
   Writer  : Tarlib.Writers.Writer;
   Result  : Tarlib.Errors.Status;
   Payload : constant Ada.Streams.Stream_Element_Array :=
     To_Bytes ("hello from tarlib" & Character'Val (10));
begin
   Tarlib.Files.Create_Write (Sink, "example.tar", Result);
   Require_Success (Result, "create output");
   Tarlib.Writers.Initialize (Writer, Sink, Result);
   Require_Success (Result, "initialize writer");

   Tarlib.Writers.Add_Directory (Writer, "docs/", Result);
   Require_Success (Result, "add directory");
   Tarlib.Writers.Begin_File (Writer, "docs/hello.txt", Payload'Length, Result);
   Require_Success (Result, "begin file");
   Tarlib.Writers.Write (Writer, Payload, Result);
   Require_Success (Result, "write payload");
   Tarlib.Writers.End_Entry (Writer, Result);
   Require_Success (Result, "end file");
   Tarlib.Writers.Finish (Writer, Result);
   Require_Success (Result, "finish archive");
   Tarlib.Files.Close (Sink, Result);
   Require_Success (Result, "close output");

   Ada.Text_IO.Put_Line ("wrote example.tar");
end Write_Archive;
