package body Tarlib.Internal.Fields is
   use type Ada.Streams.Stream_Element_Offset;
   use type Ada.Streams.Stream_Element;
   use type Interfaces.Unsigned_64;

   NUL   : constant Ada.Streams.Stream_Element := 0;
   Space : constant Ada.Streams.Stream_Element := 32;
   Zero  : constant Ada.Streams.Stream_Element := 48;
   Seven : constant Ada.Streams.Stream_Element := 55;

   procedure Clear (Field : out Ada.Streams.Stream_Element_Array) is
   begin
      Field := [others => NUL];
   end Clear;

   procedure Put_String
     (Field  : in out Ada.Streams.Stream_Element_Array;
      Text   : String;
      Result : out Tarlib.Errors.Status)
   is
      Position : Ada.Streams.Stream_Element_Offset := Field'First;
   begin
      Clear (Field);

      if Text'Length > Field'Length then
         Result := (Code => Tarlib.Errors.Invalid_Metadata);
         return;
      end if;

      for Character_Value of Text loop
         if Character_Value = Character'Val (0) then
            Result := (Code => Tarlib.Errors.Invalid_Metadata);
            return;
         end if;

         Field (Position) :=
           Ada.Streams.Stream_Element (Character'Pos (Character_Value));
         Position := Position + 1;
      end loop;

      Result := Tarlib.Errors.OK;
   end Put_String;

   procedure Put_Octal
     (Field      : in out Ada.Streams.Stream_Element_Array;
      Value      : Interfaces.Unsigned_64;
      Terminator : Field_Terminator;
      Result     : out Tarlib.Errors.Status)
   is
      Digit_Count : constant Natural :=
        (case Terminator is
            when NUL_Terminated      => Field'Length - 1,
            when Checksum_Terminated => Field'Length - 2);
      Work         : Interfaces.Unsigned_64 := Value;
      Max_Value    : Interfaces.Unsigned_64 := 0;
      Write_Index  : Ada.Streams.Stream_Element_Offset;
   begin
      if Digit_Count = 0 then
         Result := (Code => Tarlib.Errors.Numeric_Field_Overflow);
         return;
      end if;

      for Count in 1 .. Digit_Count loop
         Max_Value := Max_Value * 8 + 7;
      end loop;

      if Value > Max_Value then
         Result := (Code => Tarlib.Errors.Numeric_Field_Overflow);
         return;
      end if;

      Field := [others => NUL];
      for Offset in 0 .. Digit_Count - 1 loop
         Write_Index :=
           Field'First
           + Ada.Streams.Stream_Element_Offset (Digit_Count - 1 - Offset);
         Field (Write_Index) :=
           Ada.Streams.Stream_Element
             (Interfaces.Unsigned_64 (Zero) + (Work mod 8));
         Work := Work / 8;
      end loop;

      case Terminator is
         when NUL_Terminated =>
            Field (Field'Last) := NUL;
         when Checksum_Terminated =>
            Field (Field'Last - 1) := NUL;
            Field (Field'Last) := Space;
      end case;

      Result := Tarlib.Errors.OK;
   end Put_Octal;

   function Text_Length
     (Field : Ada.Streams.Stream_Element_Array) return Natural
   is
      Length : Natural := 0;
   begin
      for Byte of Field loop
         exit when Byte = NUL;
         Length := Length + 1;
      end loop;

      return Length;
   end Text_Length;

   procedure Get_Octal
     (Field  : Ada.Streams.Stream_Element_Array;
      Value  : out Interfaces.Unsigned_64;
      Result : out Tarlib.Errors.Status)
   is
      Started : Boolean := False;
   begin
      Value := 0;

      for Byte of Field loop
         if Byte = NUL or else Byte = Space then
            if Started then
               exit;
            end if;
         elsif Byte in Zero .. Seven then
            Started := True;
            declare
               Digit : constant Interfaces.Unsigned_64 :=
                 Interfaces.Unsigned_64
                   (Ada.Streams.Stream_Element'Pos (Byte)
                    - Ada.Streams.Stream_Element'Pos (Zero));
            begin
               if Value > (Interfaces.Unsigned_64'Last - Digit) / 8 then
                  Result := (Code => Tarlib.Errors.Invalid_Archive);
                  return;
               end if;
               Value := Value * 8 + Digit;
            end;
         else
            Result := (Code => Tarlib.Errors.Invalid_Archive);
            return;
         end if;
      end loop;

      Result := Tarlib.Errors.OK;
   end Get_Octal;

   procedure Get_Numeric
     (Field  : Ada.Streams.Stream_Element_Array;
      Value  : out Interfaces.Unsigned_64;
      Result : out Tarlib.Errors.Status)
   is
      First_Value : constant Natural :=
        Ada.Streams.Stream_Element'Pos (Field (Field'First));
   begin
      if First_Value < 128 then
         Get_Octal (Field, Value, Result);
         return;
      end if;

      if First_Value >= 192 then
         Result := (Code => Tarlib.Errors.Invalid_Archive);
         return;
      end if;

      Value :=
        Interfaces.Unsigned_64 (First_Value - 128);
      for Index in Field'First + 1 .. Field'Last loop
         declare
            Byte_Value : constant Interfaces.Unsigned_64 :=
              Interfaces.Unsigned_64
                (Ada.Streams.Stream_Element'Pos (Field (Index)));
         begin
            if Value > (Interfaces.Unsigned_64'Last - Byte_Value) / 256 then
               Result := (Code => Tarlib.Errors.Invalid_Archive);
               return;
            end if;

            Value := Value * 256 + Byte_Value;
         end;
      end loop;

      Result := Tarlib.Errors.OK;
   end Get_Numeric;
end Tarlib.Internal.Fields;
