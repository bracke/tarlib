with Ada.Streams;
with Tarlib.Errors;
with Tarlib.Outputs;

package Tarlib.Test_Outputs is
   type Memory_Sink is new Tarlib.Outputs.Output_Sink with private;

   procedure Reset (Sink : in out Memory_Sink);

   procedure Fail_After
     (Sink  : in out Memory_Sink;
      Count : Natural);

   overriding procedure Write
     (Sink   : in out Memory_Sink;
      Data   : Ada.Streams.Stream_Element_Array;
      Result : out Tarlib.Errors.Status);

   function Length (Sink : Memory_Sink) return Natural;

   function Element
     (Sink  : Memory_Sink;
      Index : Positive) return Ada.Streams.Stream_Element;

   function Bytes (Sink : Memory_Sink) return Ada.Streams.Stream_Element_Array;

private
   Capacity : constant Natural := 65_536;

   type Buffer_Type is
     array (Positive range 1 .. Capacity) of Ada.Streams.Stream_Element;

   type Memory_Sink is new Tarlib.Outputs.Output_Sink with record
      Buffer     : Buffer_Type := [others => 0];
      Last       : Natural := 0;
      Fail_Limit : Natural := Natural'Last;
   end record;
end Tarlib.Test_Outputs;
