package body Tarlib.Errors is
   function Is_Success (Result : Status) return Boolean is
   begin
      return Result.Code = Success;
   end Is_Success;
end Tarlib.Errors;
