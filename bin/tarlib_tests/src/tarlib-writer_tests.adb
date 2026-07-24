with Ada.Streams;
with AUnit.Assertions;
with Tarlib.Entries;
with Tarlib.Errors;
with Tarlib.Test_Fixtures;
with Tarlib.Test_Outputs;
with Tarlib.Writers;

package body Tarlib.Writer_Tests is
   use AUnit.Assertions;
   use type Tarlib.Errors.Status_Code;
   use type Tarlib.Writers.Writer_State;

   overriding function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("writer state machine");
   end Name;

   procedure Test_Initialization (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Sink   : aliased Tarlib.Test_Outputs.Memory_Sink;
      Writer : Tarlib.Writers.Writer;
      Result : Tarlib.Errors.Status;
   begin
      Assert
        (Tarlib.Writers.State (Writer) = Tarlib.Writers.Uninitialized,
         "initial state");
      Tarlib.Writers.Initialize (Writer, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "initialize succeeds");
      Assert (Tarlib.Writers.State (Writer) = Tarlib.Writers.Ready, "ready");
      Tarlib.Writers.Initialize (Writer, Sink, Result);
      Assert (Result.Code = Tarlib.Errors.Invalid_State, "double initialize rejected");
   end Test_Initialization;

   procedure Test_Invalid_Sequences
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Sink   : aliased Tarlib.Test_Outputs.Memory_Sink;
      Writer : Tarlib.Writers.Writer;
      Result : Tarlib.Errors.Status;
      Bytes  : constant Ada.Streams.Stream_Element_Array :=
        Tarlib.Test_Fixtures.To_Bytes ("abc");
   begin
      Tarlib.Writers.Write (Writer, Bytes, Result);
      Assert (Result.Code = Tarlib.Errors.Invalid_State, "write before init rejected");
      Tarlib.Writers.Initialize (Writer, Sink, Result);
      Tarlib.Writers.Write (Writer, Bytes, Result);
      Assert (Result.Code = Tarlib.Errors.Invalid_State, "write outside entry rejected");
      Tarlib.Writers.Begin_File (Writer, "a", 3, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "begin file succeeds");
      Tarlib.Writers.Begin_File (Writer, "b", 0, Result);
      Assert (Result.Code = Tarlib.Errors.Invalid_State, "begin while active rejected");
      Tarlib.Writers.Write
        (Writer, Tarlib.Test_Fixtures.To_Bytes ("abcd"), Result);
      Assert (Result.Code = Tarlib.Errors.Too_Much_Entry_Data, "too much rejected");
      Tarlib.Writers.End_Entry (Writer, Result);
      Assert (Result.Code = Tarlib.Errors.Too_Little_Entry_Data, "too little rejected");
   end Test_Invalid_Sequences;

   procedure Test_Exact_Completion
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Sink   : aliased Tarlib.Test_Outputs.Memory_Sink;
      Writer : Tarlib.Writers.Writer;
      Result : Tarlib.Errors.Status;
   begin
      Tarlib.Writers.Initialize (Writer, Sink, Result);
      Tarlib.Writers.Begin_File (Writer, "a", 3, Result);
      Tarlib.Writers.Write (Writer, Tarlib.Test_Fixtures.To_Bytes ("a"), Result);
      Assert (Result.Code = Tarlib.Errors.Success, "first chunk succeeds");
      Tarlib.Writers.Write (Writer, Tarlib.Test_Fixtures.To_Bytes ("bc"), Result);
      Assert (Result.Code = Tarlib.Errors.Success, "second chunk succeeds");
      Tarlib.Writers.End_Entry (Writer, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "end succeeds at exact size");
      Assert (Tarlib.Writers.State (Writer) = Tarlib.Writers.Ready, "ready after end");
   end Test_Exact_Completion;

   procedure Test_Directory_Write_Rejected
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Sink   : aliased Tarlib.Test_Outputs.Memory_Sink;
      Writer : Tarlib.Writers.Writer;
      Result : Tarlib.Errors.Status;
   begin
      Tarlib.Writers.Initialize (Writer, Sink, Result);
      Tarlib.Writers.Begin_Entry
        (Writer, "dir/", Tarlib.Entries.Directory, 0,
         Tarlib.Entries.Default_Metadata (Tarlib.Entries.Directory), Result);
      Assert (Result.Code = Tarlib.Errors.Success, "directory begin succeeds");
      Tarlib.Writers.Write (Writer, Tarlib.Test_Fixtures.To_Bytes ("x"), Result);
      Assert
        (Result.Code = Tarlib.Errors.Invalid_Entry_Kind,
         "directory data rejected");
      Tarlib.Writers.End_Entry (Writer, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "directory end succeeds");
   end Test_Directory_Write_Rejected;

   procedure Test_Finish_And_Failure
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Sink   : aliased Tarlib.Test_Outputs.Memory_Sink;
      Writer : Tarlib.Writers.Writer;
      Result : Tarlib.Errors.Status;
      Failed_Sink   : aliased Tarlib.Test_Outputs.Memory_Sink;
      Failed_Writer : Tarlib.Writers.Writer;
   begin
      Tarlib.Writers.Initialize (Writer, Sink, Result);
      Tarlib.Writers.Finish (Writer, Result);
      Assert (Result.Code = Tarlib.Errors.Success, "finish succeeds");
      Assert (Tarlib.Writers.State (Writer) = Tarlib.Writers.Finished, "finished state");
      Tarlib.Writers.Finish (Writer, Result);
      Assert (Result.Code = Tarlib.Errors.Already_Finished, "double finish rejected");
      Tarlib.Writers.Begin_File (Writer, "late", 0, Result);
      Assert (Result.Code = Tarlib.Errors.Already_Finished, "begin after finish rejected");

      Tarlib.Test_Outputs.Fail_After (Failed_Sink, 0);
      Tarlib.Writers.Initialize (Failed_Writer, Failed_Sink, Result);
      Tarlib.Writers.Begin_File (Failed_Writer, "a", 0, Result);
      Assert (Result.Code = Tarlib.Errors.Output_Failure, "header output failure reported");
      Assert
        (Tarlib.Writers.State (Failed_Writer) = Tarlib.Writers.Failed,
         "failed state is terminal");
      Tarlib.Writers.Finish (Failed_Writer, Result);
      Assert (Result.Code = Tarlib.Errors.Output_Failure, "failed writer stays failed");
   end Test_Finish_And_Failure;

   overriding procedure Register_Tests (T : in out Test_Case) is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine
        (T, Test_Initialization'Access, "initialization");
      Registration.Register_Routine
        (T, Test_Invalid_Sequences'Access, "invalid call sequences");
      Registration.Register_Routine
        (T, Test_Exact_Completion'Access, "exact data completion");
      Registration.Register_Routine
        (T, Test_Directory_Write_Rejected'Access, "directory write rejection");
      Registration.Register_Routine
        (T, Test_Finish_And_Failure'Access, "finish and output failure");
   end Register_Tests;
end Tarlib.Writer_Tests;
