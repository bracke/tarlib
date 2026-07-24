with Tarlib.Archive_Tests;
with Tarlib.Field_Tests;
with Tarlib.Header_Tests;
with Tarlib.Path_Tests;
with Tarlib.Writer_Tests;

package body Tarlib.Test_Suites is
   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite :=
        AUnit.Test_Suites.New_Suite;
   begin
      Result.Add_Test (new Tarlib.Field_Tests.Test_Case);
      Result.Add_Test (new Tarlib.Path_Tests.Test_Case);
      Result.Add_Test (new Tarlib.Header_Tests.Test_Case);
      Result.Add_Test (new Tarlib.Writer_Tests.Test_Case);
      Result.Add_Test (new Tarlib.Archive_Tests.Test_Case);
      return Result;
   end Suite;
end Tarlib.Test_Suites;
