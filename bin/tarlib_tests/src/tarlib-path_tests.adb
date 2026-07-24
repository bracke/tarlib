with AUnit.Assertions;
with Tarlib.Errors;
with Tarlib.Internal.Paths;

package body Tarlib.Path_Tests is
   use AUnit.Assertions;
   use type Tarlib.Errors.Status_Code;

   overriding function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("USTAR path validation and splitting");
   end Name;

   function Repeat (Ch : Character; Count : Natural) return String is
      Result : String (1 .. Count);
   begin
      for Index in Result'Range loop
         Result (Index) := Ch;
      end loop;
      return Result;
   end Repeat;

   procedure Test_Short_And_Full_Name
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Short : constant Tarlib.Internal.Paths.Path_Split :=
        Tarlib.Internal.Paths.Split ("dir/file.txt");
      Full : constant Tarlib.Internal.Paths.Path_Split :=
        Tarlib.Internal.Paths.Split (Repeat ('a', 100));
   begin
      Assert (Short.Status.Code = Tarlib.Errors.Success, "short path accepted");
      Assert (Short.Name_Length = 12, "short name length");
      Assert (Short.Prefix_Length = 0, "short path has no prefix");
      Assert (Full.Status.Code = Tarlib.Errors.Success, "100-byte name accepted");
      Assert (Full.Name_Length = 100, "full name length");
   end Test_Short_And_Full_Name;

   procedure Test_Prefix_Splits (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Prefix : constant String := Repeat ('p', 60) & "/" & Repeat ('q', 60);
      Path   : constant String := Prefix & "/" & Repeat ('n', 100);
      Split  : constant Tarlib.Internal.Paths.Path_Split :=
        Tarlib.Internal.Paths.Split (Path);
      Longest : constant String := Repeat ('a', 155) & "/" & Repeat ('b', 100);
      Longest_Split : constant Tarlib.Internal.Paths.Path_Split :=
        Tarlib.Internal.Paths.Split (Longest);
   begin
      Assert (Split.Status.Code = Tarlib.Errors.Success, "split path accepted");
      Assert (Split.Prefix_Length = Prefix'Length, "deterministic last valid slash");
      Assert (Split.Name_Length = 100, "split name length");
      Assert (Longest_Split.Status.Code = Tarlib.Errors.Success, "longest split accepted");
      Assert (Longest_Split.Prefix_Length = 155, "longest prefix");
      Assert (Longest_Split.Name_Length = 100, "longest name");
   end Test_Prefix_Splits;

   procedure Test_Invalid_Paths (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Empty    : constant Tarlib.Internal.Paths.Path_Split :=
        Tarlib.Internal.Paths.Split ("");
      Absolute : constant Tarlib.Internal.Paths.Path_Split :=
        Tarlib.Internal.Paths.Split ("/etc/passwd");
      Dot_Dot  : constant Tarlib.Internal.Paths.Path_Split :=
        Tarlib.Internal.Paths.Split ("a/../b");
      NUL_Path : constant String := "a" & Character'Val (0) & "b";
      NUL_Split : constant Tarlib.Internal.Paths.Path_Split :=
        Tarlib.Internal.Paths.Split (NUL_Path);
      Too_Long : constant Tarlib.Internal.Paths.Path_Split :=
        Tarlib.Internal.Paths.Split (Repeat ('x', 101));
   begin
      Assert (Empty.Status.Code = Tarlib.Errors.Invalid_Path, "empty rejected");
      Assert (Absolute.Status.Code = Tarlib.Errors.Invalid_Path, "absolute rejected");
      Assert (Dot_Dot.Status.Code = Tarlib.Errors.Invalid_Path, ".. rejected");
      Assert (NUL_Split.Status.Code = Tarlib.Errors.Invalid_Path, "NUL rejected");
      Assert (Too_Long.Status.Code = Tarlib.Errors.Path_Too_Long, "no split rejected");
   end Test_Invalid_Paths;

   procedure Test_Archive_Path_Validation
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Long_Path : constant String := "long/" & Repeat ('x', 120);
      Valid     : constant Tarlib.Errors.Status :=
        Tarlib.Internal.Paths.Validate_Archive_Path (Long_Path);
      Absolute  : constant Tarlib.Errors.Status :=
        Tarlib.Internal.Paths.Validate_Archive_Path ("/etc/passwd");
      Dot_Dot   : constant Tarlib.Errors.Status :=
        Tarlib.Internal.Paths.Validate_Archive_Path ("a/../b");
   begin
      Assert
        (Tarlib.Internal.Paths.Split (Long_Path).Status.Code =
         Tarlib.Errors.Path_Too_Long,
         "long path does not fit USTAR");
      Assert
        (Valid.Code = Tarlib.Errors.Success,
         "long archive-relative path accepted");
      Assert
        (Absolute.Code = Tarlib.Errors.Invalid_Path,
         "absolute path rejected");
      Assert
        (Dot_Dot.Code = Tarlib.Errors.Invalid_Path,
         "parent path rejected");
   end Test_Archive_Path_Validation;

   procedure Test_Directory_Trailing_Slash
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Split : constant Tarlib.Internal.Paths.Path_Split :=
        Tarlib.Internal.Paths.Split ("dir/");
   begin
      Assert (Split.Status.Code = Tarlib.Errors.Success, "directory slash is preserved");
      Assert (Split.Name_Length = 4, "directory slash counts in name");
   end Test_Directory_Trailing_Slash;

   overriding procedure Register_Tests (T : in out Test_Case) is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine
        (T, Test_Short_And_Full_Name'Access, "short and full name paths");
      Registration.Register_Routine
        (T, Test_Prefix_Splits'Access, "prefix/name split paths");
      Registration.Register_Routine
        (T, Test_Invalid_Paths'Access, "invalid path rejection");
      Registration.Register_Routine
        (T, Test_Archive_Path_Validation'Access,
         "archive path validation");
      Registration.Register_Routine
        (T, Test_Directory_Trailing_Slash'Access, "directory trailing slash policy");
   end Register_Tests;
end Tarlib.Path_Tests;
