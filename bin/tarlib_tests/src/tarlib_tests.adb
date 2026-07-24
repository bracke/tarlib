with AUnit.Reporter.Text;
with AUnit.Run;
with Tarlib.Test_Suites;

procedure Tarlib_Tests is
   procedure Runner is new AUnit.Run.Test_Runner (Tarlib.Test_Suites.Suite);
   Reporter : AUnit.Reporter.Text.Text_Reporter;
begin
   Runner (Reporter);
end Tarlib_Tests;
