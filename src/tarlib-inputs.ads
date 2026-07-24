with Ada.Streams;
with Tarlib.Errors;

package Tarlib.Inputs
  with Preelaborate
is
   --  Blocking caller-owned input abstraction.

   type Input_Source is limited interface;
   --  Interface implemented by archive sources. The caller owns object
   --  creation, finalization, opening, and closing.

   procedure Read
     (Source : in out Input_Source;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Tarlib.Errors.Status) is abstract;
   --  Read bytes into Data before returning.
   --  @param Source Caller-owned source object.
   --  @param Data Destination buffer.
   --  @param Last Last written index, or Data'First - 1 at end of input.
   --  @param Result Success or Input_Failure.
end Tarlib.Inputs;
