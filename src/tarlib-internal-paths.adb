package body Tarlib.Internal.Paths is
   use type Tarlib.Errors.Status_Code;

   function Has_Dot_Dot_Component (Path : String) return Boolean is
      Start : Positive := Path'First;
   begin
      for Index in Path'Range loop
         if Path (Index) = '/' then
            if Index - Start = 2 and then Path (Start .. Index - 1) = ".." then
               return True;
            end if;
            if Index = Path'Last then
               return False;
            end if;
            Start := Index + 1;
         end if;
      end loop;

      return Path'Last - Start + 1 = 2 and then Path (Start .. Path'Last) = "..";
   end Has_Dot_Dot_Component;

   function Has_NUL (Path : String) return Boolean is
   begin
      for Character_Value of Path loop
         if Character_Value = Character'Val (0) then
            return True;
         end if;
      end loop;
      return False;
   end Has_NUL;

   function Split (Path : String) return Path_Split is
      Result : Path_Split;
   begin
      if Path'Length = 0 then
         Result.Status := (Code => Tarlib.Errors.Invalid_Path);
         return Result;
      end if;

      if Path (Path'First) = '/' or else Has_NUL (Path)
        or else Has_Dot_Dot_Component (Path)
      then
         Result.Status := (Code => Tarlib.Errors.Invalid_Path);
         return Result;
      end if;

      if Path'Length <= 100 then
         Result.Name_First := Path'First;
         Result.Name_Last := Path'Last;
         Result.Name_Length := Path'Length;
         Result.Prefix_First := Path'First;
         Result.Prefix_Last := Path'First - 1;
         Result.Prefix_Length := 0;
         return Result;
      end if;

      for Slash in reverse Path'Range loop
         if Path (Slash) = '/' and then Slash > Path'First and then Slash < Path'Last then
            declare
               Prefix_Length : constant Natural := Slash - Path'First;
               Name_Length   : constant Natural := Path'Last - Slash;
            begin
               if Prefix_Length <= 155 and then Name_Length <= 100 then
                  Result.Prefix_First := Path'First;
                  Result.Prefix_Last := Slash - 1;
                  Result.Prefix_Length := Prefix_Length;
                  Result.Name_First := Slash + 1;
                  Result.Name_Last := Path'Last;
                  Result.Name_Length := Name_Length;
                  return Result;
               end if;
            end;
         end if;
      end loop;

      Result.Status := (Code => Tarlib.Errors.Path_Too_Long);
      return Result;
   end Split;

   function Validate_Archive_Path (Path : String) return Tarlib.Errors.Status is
      Result : constant Path_Split := Split (Path);
   begin
      if Result.Status.Code = Tarlib.Errors.Path_Too_Long then
         return Tarlib.Errors.OK;
      else
         return Result.Status;
      end if;
   end Validate_Archive_Path;
end Tarlib.Internal.Paths;
