with Ada.Streams;
with AUnit.Assertions;
with Tarlib.Errors;
with Tarlib.Test_Fixtures;
with Tarlib.Test_Outputs;
with Tarlib.Writers;

package body Tarlib.Archive_Tests is
   use AUnit.Assertions;
   use type Ada.Streams.Stream_Element;
   use type Tarlib.Errors.Status_Code;

   overriding function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("archive byte layout");
   end Name;

   procedure Finish_Archive
     (Sink   : in out Tarlib.Test_Outputs.Memory_Sink;
      Writer : in out Tarlib.Writers.Writer) is
      Result : Tarlib.Errors.Status;
   begin
      Tarlib.Writers.Finish (Writer, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "finish succeeds");
      Assert (Tarlib.Test_Outputs.Length (Sink) >= 1024, "archive has terminators");
   end Finish_Archive;

   procedure Test_Empty_Archive (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Sink   : aliased Tarlib.Test_Outputs.Memory_Sink;
      Writer : Tarlib.Writers.Writer;
      Result : Tarlib.Errors.Status;
      Data   : Ada.Streams.Stream_Element_Array (1 .. 1024);
   begin
      Tarlib.Writers.Initialize (Writer, Sink, Result);
      Finish_Archive (Sink, Writer);
      Assert (Tarlib.Test_Outputs.Length (Sink) = 1024, "empty archive length");
      Data := Tarlib.Test_Outputs.Bytes (Sink);
      Assert (Tarlib.Test_Fixtures.Is_Zero_Block (Data, 1), "first terminator");
      Assert (Tarlib.Test_Fixtures.Is_Zero_Block (Data, 513), "second terminator");
   end Test_Empty_Archive;

   procedure Test_File_Sizes (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);

      procedure Check (Name : String; Content : String; Expected_Length : Natural) is
         Sink   : aliased Tarlib.Test_Outputs.Memory_Sink;
         Writer : Tarlib.Writers.Writer;
         Result : Tarlib.Errors.Status;
      begin
         Tarlib.Writers.Initialize (Writer, Sink, Result);
         Tarlib.Writers.Begin_File (Writer, Name, Content'Length, Result);
         Assert (Result.Code = Tarlib.Errors.Success, Name & " begin");
         Tarlib.Writers.Write (Writer, Tarlib.Test_Fixtures.To_Bytes (Content), Result);
         Assert (Result.Code = Tarlib.Errors.Success, Name & " write");
         Tarlib.Writers.End_Entry (Writer, Result);
         Assert (Result.Code = Tarlib.Errors.Success, Name & " end");
         Tarlib.Writers.Finish (Writer, Result);
         Assert (Result.Code = Tarlib.Errors.Success, Name & " finish");
         Assert (Tarlib.Test_Outputs.Length (Sink) = Expected_Length, Name & " length");
      end Check;
   begin
      Check ("zero", "", 1536);
      Check ("one", "x", 2048);
      Check ("exact", (1 .. 512 => 'x'), 2048);
      Check ("over", (1 .. 513 => 'x'), 2560);
   end Test_File_Sizes;

   procedure Test_Multiple_Entries
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Sink   : aliased Tarlib.Test_Outputs.Memory_Sink;
      Writer : Tarlib.Writers.Writer;
      Result : Tarlib.Errors.Status;
      Data   : Ada.Streams.Stream_Element_Array (1 .. 2560);
   begin
      Tarlib.Writers.Initialize (Writer, Sink, Result);
      Tarlib.Writers.Add_Directory (Writer, "dir/", Result);
      Assert (Result.Code = Tarlib.Errors.Success, "directory added");
      Tarlib.Writers.Begin_File (Writer, "dir/file.txt", 5, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "file begin");
      Tarlib.Writers.Write (Writer, Tarlib.Test_Fixtures.To_Bytes ("he"), Result);
      Assert (Result.Code = Tarlib.Errors.Success, "first chunk");
      Tarlib.Writers.Write (Writer, Tarlib.Test_Fixtures.To_Bytes ("llo"), Result);
      Assert (Result.Code = Tarlib.Errors.Success, "second chunk");
      Tarlib.Writers.End_Entry (Writer, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "file end");
      Tarlib.Writers.Finish (Writer, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "finish");
      Assert (Tarlib.Test_Outputs.Length (Sink) = 2560, "directory plus file length");
      Data := Tarlib.Test_Outputs.Bytes (Sink);
      Assert (Data (513) = Character'Pos ('d'), "file header begins after directory block");
      Assert (Data (1025) = Character'Pos ('h'), "file content follows header");
      Assert (Tarlib.Test_Fixtures.Is_Zero_Block (Data, 1537), "first terminator block");
      Assert (Tarlib.Test_Fixtures.Is_Zero_Block (Data, 2049), "second terminator block");
   end Test_Multiple_Entries;

   procedure Test_Determinism (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);

      procedure Build (Sink : in out Tarlib.Test_Outputs.Memory_Sink) is
         Writer : Tarlib.Writers.Writer;
         Result : Tarlib.Errors.Status;
      begin
         Tarlib.Writers.Initialize (Writer, Sink, Result);
         Tarlib.Writers.Begin_File (Writer, "a", 3, Result);
         Tarlib.Writers.Write (Writer, Tarlib.Test_Fixtures.To_Bytes ("abc"), Result);
         Tarlib.Writers.End_Entry (Writer, Result);
         Tarlib.Writers.Finish (Writer, Result);
      end Build;

      A : aliased Tarlib.Test_Outputs.Memory_Sink;
      B : aliased Tarlib.Test_Outputs.Memory_Sink;
   begin
      Build (A);
      Build (B);
      Assert (Tarlib.Test_Outputs.Length (A) = Tarlib.Test_Outputs.Length (B), "same length");
      for Index in 1 .. Tarlib.Test_Outputs.Length (A) loop
         Assert
           (Tarlib.Test_Outputs.Element (A, Index) =
            Tarlib.Test_Outputs.Element (B, Index),
            "same byte");
      end loop;
   end Test_Determinism;

   overriding procedure Register_Tests (T : in out Test_Case) is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine
        (T, Test_Empty_Archive'Access, "empty archive");
      Registration.Register_Routine
        (T, Test_File_Sizes'Access, "file size padding");
      Registration.Register_Routine
        (T, Test_Multiple_Entries'Access, "directory plus file");
      Registration.Register_Routine
        (T, Test_Determinism'Access, "deterministic output");
   end Register_Tests;
end Tarlib.Archive_Tests;
