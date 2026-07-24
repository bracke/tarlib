with Ada.Streams;
with Tarlib.Errors;

package Tarlib.Outputs
  with Preelaborate
is
   --  Blocking caller-owned output abstraction.

   type Output_Sink is limited interface;
   --  Interface implemented by archive destinations. The caller owns object
   --  creation, finalization, opening, and closing.

   procedure Write
     (Sink   : in out Output_Sink;
      Data   : Ada.Streams.Stream_Element_Array;
      Result : out Tarlib.Errors.Status) is abstract;
   --  Write Data to Sink before returning.
   --  @param Sink Caller-owned destination object.
   --  @param Data Bytes to append to the destination stream.
   --  @param Result Success or Output_Failure.
end Tarlib.Outputs;
