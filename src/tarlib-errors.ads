package Tarlib.Errors
  with Pure
is
   --  Structured status model used for all ordinary library failures.

   type Status_Code is
     (Success,
      Invalid_State,
      Invalid_Path,
      Path_Too_Long,
      Invalid_Entry_Kind,
      Invalid_Metadata,
      Invalid_Size,
      Invalid_Archive,
      Numeric_Field_Overflow,
      Too_Much_Entry_Data,
      Too_Little_Entry_Data,
      Input_Failure,
      Output_Failure,
      Already_Finished,
      Internal_Error);
   --  Deterministic result code. Input_Failure, Output_Failure, and
   --  Internal_Error are terminal for stream processors.

   type Status is record
      Code : Status_Code := Success;
   end record;
   --  Heap-free operation status.

   OK : constant Status := (Code => Success);
   --  Successful status value.

   function Is_Success (Result : Status) return Boolean;
   --  Test whether Result is Success.
   --  @param Result Status to inspect.
   --  @return True when Result.Code is Success.
end Tarlib.Errors;
