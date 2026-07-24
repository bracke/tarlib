with Tarlib.Errors;

package Tarlib.Internal.Paths
  with Pure
is
   --  Archive path validation and POSIX USTAR name/prefix splitting.

   subtype Name_Index is Natural range 0 .. 100;
   --  Length of the USTAR name field content.

   subtype Prefix_Index is Natural range 0 .. 155;
   --  Length of the USTAR prefix field content.

   type Path_Split is record
      Status        : Tarlib.Errors.Status := Tarlib.Errors.OK;
      Name_First    : Positive := 1;
      Name_Last     : Natural := 0;
      Prefix_First  : Positive := 1;
      Prefix_Last   : Natural := 0;
      Name_Length   : Name_Index := 0;
      Prefix_Length : Prefix_Index := 0;
   end record;
   --  Split result. Prefix_Last < Prefix_First means no prefix.

   function Split (Path : String) return Path_Split;
   --  Validate Path and choose a deterministic USTAR split.
   --  @param Path Archive path using / separators and no native normalization.
   --  @return Success with byte ranges or a path status.

   function Validate_Archive_Path (Path : String) return Tarlib.Errors.Status;
   --  Validate archive-relative path syntax without requiring USTAR fit.
   --  @param Path Archive path using / separators and no native normalization.
   --  @return Success, Invalid_Path, or Path_Too_Long.
end Tarlib.Internal.Paths;
