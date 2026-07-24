with Ada.Streams;
with Tarlib.Errors;
with Tarlib.Inputs;
with Tarlib.Outputs;

package Tarlib.Test_Outputs is
   type Memory_Sink is new Tarlib.Outputs.Output_Sink
     and Tarlib.Inputs.Input_Source with private;

   procedure Reset (Sink : in out Memory_Sink);

   procedure Fail_After
     (Sink  : in out Memory_Sink;
      Count : Natural);

   overriding procedure Write
     (Sink   : in out Memory_Sink;
      Data   : Ada.Streams.Stream_Element_Array;
      Result : out Tarlib.Errors.Status);

   overriding procedure Read
     (Sink   : in out Memory_Sink;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Tarlib.Errors.Status);

   procedure Rewind (Sink : in out Memory_Sink);

   function Length (Sink : Memory_Sink) return Natural;

   function Element
     (Sink  : Memory_Sink;
      Index : Positive) return Ada.Streams.Stream_Element;

   procedure Set_Element
     (Sink  : in out Memory_Sink;
      Index : Positive;
      Value : Ada.Streams.Stream_Element);

   function Bytes (Sink : Memory_Sink) return Ada.Streams.Stream_Element_Array;

private
   Capacity : constant Natural := 65_536;

   type Buffer_Type is
     array (Positive range 1 .. Capacity) of Ada.Streams.Stream_Element;

   type Memory_Sink is new Tarlib.Outputs.Output_Sink
     and Tarlib.Inputs.Input_Source with record
      Buffer     : Buffer_Type := [others => 0];
      Last       : Natural := 0;
      Cursor     : Natural := 1;
      Fail_Limit : Natural := Natural'Last;
   end record;
end Tarlib.Test_Outputs;
