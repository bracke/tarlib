with Ada.Command_Line;
with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;

with GNAT.OS_Lib;
with Project_Tools.Files;
with Project_Tools.Processes;

procedure Check_Tarlib is
   use Ada.Text_IO;

   function Root_Directory return String is
      Current : constant String := Ada.Directories.Current_Directory;
      Root    : constant String :=
        Project_Tools.Files.Find_Root_Upward (Current, "tarlib.gpr");
   begin
      if Root = "" then
         Put_Line (Standard_Error, "tarlib root not found from " & Current);
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         raise Program_Error;
      end if;

      return Root;
   end Root_Directory;

   Root     : constant String := Root_Directory;
   Alr_Path : constant String := Project_Tools.Processes.Locate_Command ("alr");
   Errors   : Natural := 0;

   procedure Error (Message : String) is
   begin
      Errors := Errors + 1;
      Put_Line (Standard_Error, "error: " & Message);
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end Error;

   procedure Require_File (Relative_Path : String) is
   begin
      if not Project_Tools.Files.File_Exists
        (Project_Tools.Files.Join (Root, Relative_Path))
      then
         Error ("missing required file " & Relative_Path);
      end if;
   end Require_File;

   procedure Require_Text (Relative_Path : String; Pattern : String) is
      Path : constant String := Project_Tools.Files.Join (Root, Relative_Path);
   begin
      if not Project_Tools.Files.File_Contains (Path, Pattern) then
         Error
           ("missing required text in " & Relative_Path & ": " & Pattern);
      end if;
   end Require_Text;

   procedure Check_Required_Surface is
   begin
      Require_File ("alire.toml");
      Require_File ("tarlib.gpr");
      Require_File ("README.md");
      Require_File ("src/tarlib.ads");
      Require_File ("src/tarlib-readers.ads");
      Require_File ("src/tarlib-writers.ads");
      Require_File ("src/tarlib-files.ads");
      Require_File ("docs/API_GUIDE.md");
      Require_File ("docs/FORMAT_SUPPORT.md");
      Require_File ("docs/LIMITATIONS.md");
      Require_File ("docs/SECURITY.md");
      Require_File ("examples/examples.gpr");
      Require_File ("examples/write_archive.adb");
      Require_File ("examples/read_archive.adb");
      Require_File ("examples/pack_extract.adb");
      Require_File ("bin/tarlib_tests/alire.toml");
      Require_File ("bin/tarlib_tests/tarlib_tests.gpr");
      Require_File ("bin/tarlib_tests/src/tarlib_tests.adb");

      Require_Text ("alire.toml", "gnat_native = ""=15.2.1""");
      Require_Text ("README.md", "alr test");
      Require_Text ("README.md", "sequential archive reading");
      Require_Text ("README.md", "sequential archive writing");
      Require_Text ("README.md", "docs/API_GUIDE.md");
      Require_Text ("README.md", "docs/FORMAT_SUPPORT.md");
      Require_Text ("docs/API_GUIDE.md", "Tarlib.Writers");
      Require_Text ("docs/API_GUIDE.md", "Tarlib.Readers");
      Require_Text ("docs/API_GUIDE.md", "Tarlib.Files");
      Require_Text ("docs/FORMAT_SUPPORT.md", "gzip/bzip2/xz/zstd compression");
      Require_Text ("docs/LIMITATIONS.md", "Automatic multi-volume archive splitting");
      Require_Text ("docs/SECURITY.md", "Archive paths must be relative");
      Require_Text ("examples/examples.gpr", "write_archive.adb");
      Require_Text ("examples/examples.gpr", "read_archive.adb");
      Require_Text ("examples/examples.gpr", "pack_extract.adb");
      Require_Text ("bin/tarlib_tests/alire.toml", "project_tools");
      Require_Text ("bin/tarlib_tests/tarlib_tests.gpr", "with ""project_tools""");
   end Check_Required_Surface;

   procedure Require_Alire_GNAT_15 is
      Args   : constant GNAT.OS_Lib.Argument_List :=
        [1 => new String'("--non-interactive"),
         2 => new String'("exec"),
         3 => new String'("--"),
         4 => new String'("gnatls"),
         5 => new String'("--version")];
      Output : Unbounded_String;
      Status : Integer;
   begin
      Status :=
        Project_Tools.Processes.Run_Status
          (Label   => "GNAT 15 version check",
           Dir     => Root,
           Program => Alr_Path,
           Args    => Args,
           Output  => Output,
           Quiet   => True);

      if Status /= 0 then
         Error ("could not run `alr exec -- gnatls --version`");
      elsif Ada.Strings.Fixed.Index (To_String (Output), "GNATLS 15.2") = 0 then
         Error
           ("wrong Ada compiler: expected Alire-selected GNATLS 15.2.x, got: "
            & To_String (Output));
      end if;
   end Require_Alire_GNAT_15;

   procedure Run_Command
     (Label : String;
      Args  : GNAT.OS_Lib.Argument_List)
   is
      Status : Integer;
   begin
      Status :=
        Project_Tools.Processes.Run_Status
          (Label   => Label,
           Dir     => Root,
           Program => Alr_Path,
           Args    => Args,
           Quiet   => False);

      if Status /= 0 then
         Error (Label & " failed with status" & Integer'Image (Status));
      end if;
   end Run_Command;

   procedure Check_AUnit_Log is
      Log : constant String := Project_Tools.Files.Join
        (Root, "alire/alr_test_local.log");
   begin
      if not Project_Tools.Files.File_Exists (Log) then
         Error ("missing AUnit log " & Log);
         return;
      end if;

      if not Project_Tools.Files.File_Contains (Log, "Failed Assertions: 0") then
         Error ("AUnit log reports failed assertions");
      end if;

      if not Project_Tools.Files.File_Contains (Log, "Unexpected Errors: 0") then
         Error ("AUnit log reports unexpected errors");
      end if;

      if not Project_Tools.Files.File_Contains
        (Log, "[alr test] Test completed SUCCESSFULLY")
      then
         Error ("AUnit log does not contain the successful completion marker");
      end if;
   end Check_AUnit_Log;

   procedure Print_Result is
   begin
      if Errors = 0 then
         Put_Line ("tarlib checks passed");
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
      else
         Put_Line
           (Standard_Error,
            "tarlib checks failed:" & Natural'Image (Errors) & " error(s)");
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      end if;
   end Print_Result;
begin
   Project_Tools.Processes.Require_Command
     ("alr", "alr executable not found on PATH");

   Put_Line
     ("tarlib check context: root=" & Root
      & "; project_tools=../project_tools");

   Check_Required_Surface;
   Require_Alire_GNAT_15;

   if Project_Tools.Processes.Has_Argument ("--policy-only") then
      Print_Result;
      return;
   end if;

   Run_Command
     ("build tarlib",
      [1 => new String'("--non-interactive"),
       2 => new String'("build")]);
   Run_Command
     ("build tarlib examples",
      [1 => new String'("--non-interactive"),
       2 => new String'("exec"),
       3 => new String'("--"),
       4 => new String'("gprbuild"),
       5 => new String'("-P"),
       6 => new String'("examples/examples.gpr")]);
   Run_Command
     ("run tarlib AUnit suite",
      [1 => new String'("--non-interactive"),
       2 => new String'("test")]);
   Check_AUnit_Log;
   Print_Result;
end Check_Tarlib;
