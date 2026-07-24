with Ada.Streams;

package body Tarlib.Test_Outputs is
   use type Ada.Streams.Stream_Element_Offset;

   procedure Reset (Sink : in out Memory_Sink) is
   begin
      Sink.Buffer := [others => 0];
      Sink.Last := 0;
      Sink.Fail_Limit := Natural'Last;
   end Reset;

   procedure Fail_After
     (Sink  : in out Memory_Sink;
      Count : Natural) is
   begin
      Sink.Fail_Limit := Count;
   end Fail_After;

   overriding procedure Write
     (Sink   : in out Memory_Sink;
      Data   : Ada.Streams.Stream_Element_Array;
      Result : out Tarlib.Errors.Status)
   is
      Target_Last : constant Natural := Sink.Last + Data'Length;
      Position    : Natural := Sink.Last + 1;
   begin
      if Target_Last > Sink.Fail_Limit or else Target_Last > Capacity then
         Result := (Code => Tarlib.Errors.Output_Failure);
         return;
      end if;

      for Index in Data'Range loop
         Sink.Buffer (Position) := Data (Index);
         Position := Position + 1;
      end loop;
      Sink.Last := Target_Last;
      Result := Tarlib.Errors.OK;
   end Write;

   function Length (Sink : Memory_Sink) return Natural is
   begin
      return Sink.Last;
   end Length;

   function Element
     (Sink  : Memory_Sink;
      Index : Positive) return Ada.Streams.Stream_Element is
   begin
      return Sink.Buffer (Index);
   end Element;

   function Bytes (Sink : Memory_Sink) return Ada.Streams.Stream_Element_Array is
      Result : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Sink.Last));
   begin
      for Index in Result'Range loop
         Result (Index) :=
           Sink.Buffer (Natural (Index - Result'First) + 1);
      end loop;
      return Result;
   end Bytes;
end Tarlib.Test_Outputs;
