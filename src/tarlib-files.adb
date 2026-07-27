with Ada.Directories;
with Ada.Streams;
with Ada.Strings.Unbounded;

with Hostkit.Fs;
with Hostkit.Process;
with Interfaces.C;
with Interfaces.C.Strings;
with Interfaces;
with Tarlib.Entries;

package body Tarlib.Files is
   use type Ada.Streams.Stream_Element_Offset;
   use type Interfaces.C.int;
   use type Interfaces.C.unsigned;
   use type Interfaces.Unsigned_64;
   use type Tarlib.Entries.Entry_Kind;
   use type Tarlib.Errors.Status_Code;

   function Parent_Directory (Path : String) return String is
   begin
      for Index in reverse Path'Range loop
         if Path (Index) = '/' then
            if Index = Path'First then
               return "/";
            else
               return Path (Path'First .. Index - 1);
            end if;
         end if;
      end loop;

      return "";
   end Parent_Directory;

   procedure Ensure_Parent
     (Path   : String;
      Result : out Tarlib.Errors.Status)
   is
      Parent : constant String := Parent_Directory (Path);
   begin
      if Parent'Length > 0 then
         Ada.Directories.Create_Path (Parent);
      end if;
      Result := Tarlib.Errors.OK;
   exception
      when others =>
         Result := (Code => Tarlib.Errors.Output_Failure);
   end Ensure_Parent;

   function Join
     (Left  : String;
      Right : String) return String is
   begin
      if Left'Length = 0 then
         return Right;
      elsif Left (Left'Last) = '/' then
         return Left & Right;
      else
         return Left & "/" & Right;
      end if;
   end Join;

   procedure Write_Text
     (Sink   : in out File_Output_Sink;
      Text   : String;
      Result : out Tarlib.Errors.Status)
   is
      Data : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Text'Length));
   begin
      for Offset in 0 .. Text'Length - 1 loop
         Data (Data'First + Ada.Streams.Stream_Element_Offset (Offset)) :=
           Ada.Streams.Stream_Element
             (Character'Pos (Text (Text'First + Offset)));
      end loop;

      Write (Sink, Data, Result);
   end Write_Text;

   procedure Write_Incremental_Listing
     (Directory : String;
      Listing   : Tarlib.Readers.Incremental_Listing;
      Result    : out Tarlib.Errors.Status)
   is
      Sink : File_Output_Sink;
   begin
      Create_Write (Sink, Join (Directory, ".gnu-incremental-listing"), Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      for Index in 1 .. Tarlib.Readers.Incremental_Record_Count (Listing) loop
         Write_Text
           (Sink,
            (if Tarlib.Readers.Incremental_Record_Is_Directory
                  (Listing, Index)
             then "Y "
             else "N ")
            & Tarlib.Readers.Incremental_Record_Path (Listing, Index)
            & Character'Val (10),
            Result);
         if Result.Code /= Tarlib.Errors.Success then
            return;
         end if;
      end loop;

      Close (Sink, Result);
   end Write_Incremental_Listing;

   function Directory_Archive_Path (Path : String) return String is
   begin
      if Path'Length > 0 and then Path (Path'Last) = '/' then
         return Path;
      else
         return Path & "/";
      end if;
   end Directory_Archive_Path;

   procedure Apply_Mode
     (Path     : String;
      Metadata : Tarlib.Entries.Metadata;
      Options  : Extraction_Options;
      Result   : out Tarlib.Errors.Status)
   is
      function C_Chmod
        (Path : Interfaces.C.Strings.chars_ptr;
         Mode : Interfaces.C.unsigned) return Interfaces.C.int
        with Import, Convention => C, External_Name => "chmod";

      C_Path : Interfaces.C.Strings.chars_ptr;
      Status : Interfaces.C.int;
   begin
      if not Options.Apply_Permissions then
         Result := Tarlib.Errors.OK;
         return;
      end if;

      C_Path := Interfaces.C.Strings.New_String (Path);
      Status :=
        C_Chmod
          (C_Path,
           Interfaces.C.unsigned
             (Interfaces.Unsigned_32 (Metadata.Mode)));
      Interfaces.C.Strings.Free (C_Path);

      if Status = 0 then
         Result := Tarlib.Errors.OK;
      else
         Result := (Code => Tarlib.Errors.Output_Failure);
      end if;
   exception
      when others =>
         Result := (Code => Tarlib.Errors.Output_Failure);
   end Apply_Mode;

   procedure Apply_Times
     (Path     : String;
      Metadata : Tarlib.Entries.Metadata;
      Options  : Extraction_Options;
      Result   : out Tarlib.Errors.Status)
   is
      type Time_T is new Interfaces.C.long;
      type Utimbuf is record
         ATime : Time_T;
         MTime : Time_T;
      end record
        with Convention => C;

      function C_Utime
        (Path  : Interfaces.C.Strings.chars_ptr;
         Times : access constant Utimbuf) return Interfaces.C.int
        with Import, Convention => C, External_Name => "utime";

      C_Path : Interfaces.C.Strings.chars_ptr;
      Times  : aliased constant Utimbuf :=
        (ATime => Time_T (Metadata.ATime),
         MTime => Time_T (Metadata.MTime));
      Status : Interfaces.C.int;
   begin
      if not Options.Apply_Timestamps then
         Result := Tarlib.Errors.OK;
         return;
      end if;

      C_Path := Interfaces.C.Strings.New_String (Path);
      Status := C_Utime (C_Path, Times'Access);
      Interfaces.C.Strings.Free (C_Path);

      if Status = 0 then
         Result := Tarlib.Errors.OK;
      else
         Result := (Code => Tarlib.Errors.Output_Failure);
      end if;
   exception
      when others =>
         Result := (Code => Tarlib.Errors.Output_Failure);
   end Apply_Times;

   procedure Apply_Owner
     (Path     : String;
      Metadata : Tarlib.Entries.Metadata;
      Options  : Extraction_Options;
      Result   : out Tarlib.Errors.Status)
   is
   begin
      if not Options.Apply_Ownership then
         Result := Tarlib.Errors.OK;
         return;
      elsif Metadata.UID > Tarlib.Byte_Count (Interfaces.C.unsigned'Last)
        or else Metadata.GID > Tarlib.Byte_Count (Interfaces.C.unsigned'Last)
      then
         Result := (Code => Tarlib.Errors.Invalid_Metadata);
         return;
      end if;

      --  Ownership is a host fact, and one this host may not have: Hostkit
      --  answers for it rather than this binding chown itself, which is what
      --  kept the library from linking anywhere without one.
      if Hostkit.Fs.Set_Owner
        (Path, Integer (Metadata.UID), Integer (Metadata.GID))
      then
         Result := Tarlib.Errors.OK;
      else
         Result := (Code => Tarlib.Errors.Output_Failure);
      end if;
   exception
      when others =>
         Result := (Code => Tarlib.Errors.Output_Failure);
   end Apply_Owner;

   procedure Apply_Metadata
     (Path     : String;
      Metadata : Tarlib.Entries.Metadata;
      Options  : Extraction_Options;
      Result   : out Tarlib.Errors.Status) is
   begin
      Apply_Owner (Path, Metadata, Options, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Apply_Mode (Path, Metadata, Options, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Apply_Times (Path, Metadata, Options, Result);
   end Apply_Metadata;

   procedure Apply_Vendor_Metadata
     (Path    : String;
      Info    : Tarlib.Readers.Entry_Info;
      Options : Extraction_Options;
      Result  : out Tarlib.Errors.Status)
   is
      --  An argument vector, not a command line: setfacl and chattr are run
      --  directly, so nothing here is parsed by a shell and no path or ACL text
      --  has to be filtered for what a shell would do with it. The filter this
      --  replaced rejected any path holding a space, which is a legal path.
      procedure Run_Tool (Program : String; Arguments : Hostkit.String_Vectors.Vector) is
         --  Resolved first: the spawn underneath does not search PATH, and a
         --  name it cannot find fails exactly like a tool that ran and refused.
         Located     : constant String := Hostkit.Process.Locate (Program);
         Exit_Status : Integer;
         Ran         : Boolean;
      begin
         if Located = "" then
            Result := (Code => Tarlib.Errors.Output_Failure);
            return;
         end if;

         Ran := Hostkit.Process.Run (Located, Arguments, Exit_Status);
         if Ran and then Exit_Status = 0 then
            Result := Tarlib.Errors.OK;
         else
            Result := (Code => Tarlib.Errors.Output_Failure);
         end if;
      exception
         when others =>
            Result := (Code => Tarlib.Errors.Output_Failure);
      end Run_Tool;

      function Words (First : String; Second : String) return Hostkit.String_Vectors.Vector is
         Items : Hostkit.String_Vectors.Vector;
      begin
         Items.Append (Ada.Strings.Unbounded.To_Unbounded_String (First));
         Items.Append (Ada.Strings.Unbounded.To_Unbounded_String (Second));
         return Items;
      end Words;

      procedure Apply_Native_ACL (Default_ACL : Boolean; Text : String) is
         Prefix : constant String := (if Default_ACL then "d:" else "");
         Items  : Hostkit.String_Vectors.Vector;
      begin
         if Text'Length = 0 then
            Result := (Code => Tarlib.Errors.Invalid_Metadata);
            return;
         end if;

         Items.Append (Ada.Strings.Unbounded.To_Unbounded_String ("-m"));
         Items.Append
           (Ada.Strings.Unbounded.To_Unbounded_String (Prefix & Text));
         Items.Append (Ada.Strings.Unbounded.To_Unbounded_String (Path));
         Run_Tool ("setfacl", Items);
      end Apply_Native_ACL;

      procedure Apply_Native_Flags (Text : String) is
      begin
         if Text = "nodump" then
            Run_Tool ("chattr", Words ("+d", Path));
         elsif Text = "dump" then
            Run_Tool ("chattr", Words ("-d", Path));
         else
            Result := (Code => Tarlib.Errors.Invalid_Metadata);
         end if;
      end Apply_Native_Flags;

      procedure Write_Sidecar (Suffix : String; Text : String) is
         Sink : File_Output_Sink;
      begin
         Create_Write (Sink, Path & Suffix, Result);
         if Result.Code /= Tarlib.Errors.Success then
            return;
         end if;

         Write_Text (Sink, Text & Character'Val (10), Result);
         if Result.Code /= Tarlib.Errors.Success then
            return;
         end if;

         Close (Sink, Result);
      end Write_Sidecar;

      Applied : Boolean;
   begin
      if Options.Apply_Extended_Attributes then
         for Index in 1 .. Tarlib.Readers.XAttr_Count (Info) loop
            declare
               Text  : constant String :=
                 Tarlib.Readers.XAttr_Value (Info, Index);
               Bytes : Ada.Streams.Stream_Element_Array
                 (1 .. Ada.Streams.Stream_Element_Offset (Text'Length));
               Pos   : Ada.Streams.Stream_Element_Offset := Bytes'First;
            begin
               for C of Text loop
                  Bytes (Pos) :=
                    Ada.Streams.Stream_Element (Character'Pos (C));
                  Pos := Pos + 1;
               end loop;
               Applied :=
                 Hostkit.Fs.Set_Extended_Attribute
                   (Path, Tarlib.Readers.XAttr_Name (Info, Index), Bytes);
            end;
            if not Applied then
               Result := (Code => Tarlib.Errors.Output_Failure);
               return;
            end if;
         end loop;
      end if;

      if Options.Apply_ACLs then
         if Tarlib.Readers.ACL_Access (Info)'Length > 0 then
            Write_Sidecar (".schily-acl-access", Tarlib.Readers.ACL_Access (Info));
            if Result.Code /= Tarlib.Errors.Success then
               return;
            end if;
         end if;

         if Tarlib.Readers.ACL_Default (Info)'Length > 0 then
            Write_Sidecar
              (".schily-acl-default", Tarlib.Readers.ACL_Default (Info));
            if Result.Code /= Tarlib.Errors.Success then
               return;
            end if;
         end if;
      end if;

      if Options.Apply_Native_ACLs then
         if Tarlib.Readers.ACL_Access (Info)'Length > 0 then
            Apply_Native_ACL (False, Tarlib.Readers.ACL_Access (Info));
            if Result.Code /= Tarlib.Errors.Success then
               return;
            end if;
         end if;

         if Tarlib.Readers.ACL_Default (Info)'Length > 0 then
            Apply_Native_ACL (True, Tarlib.Readers.ACL_Default (Info));
            if Result.Code /= Tarlib.Errors.Success then
               return;
            end if;
         end if;
      end if;

      if Options.Apply_File_Flags
        and then Tarlib.Readers.File_Flags (Info)'Length > 0
      then
         Write_Sidecar (".libarchive-fflags", Tarlib.Readers.File_Flags (Info));
         if Result.Code /= Tarlib.Errors.Success then
            return;
         end if;
      end if;

      if Options.Apply_Native_File_Flags
        and then Tarlib.Readers.File_Flags (Info)'Length > 0
      then
         Apply_Native_Flags (Tarlib.Readers.File_Flags (Info));
         if Result.Code /= Tarlib.Errors.Success then
            return;
         end if;
      end if;

      Result := Tarlib.Errors.OK;
   exception
      when others =>
         Result := (Code => Tarlib.Errors.Output_Failure);
   end Apply_Vendor_Metadata;

   procedure Create_FIFO
     (Path     : String;
      Metadata : Tarlib.Entries.Metadata;
      Options  : Extraction_Options;
      Result   : out Tarlib.Errors.Status)
   is

      C_Path : Interfaces.C.Strings.chars_ptr;
      Status : Interfaces.C.int;
   begin
      if not Options.Create_Special_Entries then
         Result := (Code => Tarlib.Errors.Invalid_Entry_Kind);
         return;
      end if;

      Ensure_Parent (Path, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      if Hostkit.Fs.Create_FIFO
        (Path, Natural (Interfaces.Unsigned_32 (Metadata.Mode)))
      then
         Apply_Metadata (Path, Metadata, Options, Result);
      else
         Result := (Code => Tarlib.Errors.Output_Failure);
      end if;
   exception
      when others =>
         Result := (Code => Tarlib.Errors.Output_Failure);
   end Create_FIFO;

   procedure Create_Device
     (Path     : String;
      Kind     : Tarlib.Entries.Entry_Kind;
      Device   : Tarlib.Entries.Device_Numbers;
      Metadata : Tarlib.Entries.Metadata;
      Options  : Extraction_Options;
      Result   : out Tarlib.Errors.Status)
   is

      S_IFCHR : constant Interfaces.C.unsigned := 8#020000#;
      S_IFBLK : constant Interfaces.C.unsigned := 8#060000#;
      C_Path  : Interfaces.C.Strings.chars_ptr;
      Mode    : Interfaces.C.unsigned;
      Major   : constant Interfaces.Unsigned_32 :=
        Interfaces.Unsigned_32 (Device.Major);
      Minor   : constant Interfaces.Unsigned_32 :=
        Interfaces.Unsigned_32 (Device.Minor);
      Major_64 : constant Interfaces.Unsigned_64 :=
        Interfaces.Unsigned_64 (Major);
      Minor_64 : constant Interfaces.Unsigned_64 :=
        Interfaces.Unsigned_64 (Minor);
      Dev_64   : constant Interfaces.Unsigned_64 :=
        (case Options.Device_Layout is
            when Native_Device_Layout | Linux_Device_Layout =>
              (Minor_64 and 16#0000_00FF#)
              or ((Major_64 and 16#0000_0FFF#) * 2**8)
              or ((Minor_64 and not 16#0000_00FF#) * 2**12)
              or ((Major_64 and not 16#0000_0FFF#) * 2**32),
            when BSD_Device_Layout =>
              Major_64 * 2**8 + Minor_64,
            when Solaris_Device_Layout =>
              Major_64 * 2**18 + Minor_64);
      Dev     : constant Interfaces.C.unsigned_long :=
        Interfaces.C.unsigned_long (Dev_64);
      Status  : Interfaces.C.int;
   begin
      if not Options.Create_Special_Entries then
         Result := (Code => Tarlib.Errors.Invalid_Entry_Kind);
         return;
      end if;

      Ensure_Parent (Path, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      --  The major/minor layout stays here: which one wrote the archive is a
      --  fact about the archive, not about this host. Hostkit takes the
      --  encoded value and makes the node, or says it cannot.
      if Hostkit.Fs.Create_Device
        (Path,
         (if Kind = Tarlib.Entries.Character_Device
          then Hostkit.Fs.Character_Device else Hostkit.Fs.Block_Device),
         Interfaces.Unsigned_64 (Dev),
         Natural (Interfaces.Unsigned_32 (Metadata.Mode)))
      then
         Apply_Metadata (Path, Metadata, Options, Result);
      else
         Result := (Code => Tarlib.Errors.Output_Failure);
      end if;
   exception
      when others =>
         Result := (Code => Tarlib.Errors.Output_Failure);
   end Create_Device;

   procedure Create_Symbolic_Link
     (Target_Path : String;
      Link_Path   : String;
      Result      : out Tarlib.Errors.Status)
   is

   begin
      Ensure_Parent (Link_Path, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      if Hostkit.Fs.Create_Link (Target_Path, Link_Path) then
         Result := Tarlib.Errors.OK;
      else
         Result := (Code => Tarlib.Errors.Output_Failure);
      end if;
   exception
      when others =>
         Result := (Code => Tarlib.Errors.Output_Failure);
   end Create_Symbolic_Link;

   procedure Create_Hard_Link
     (Existing_Path : String;
      New_Path      : String;
      Result        : out Tarlib.Errors.Status)
   is

   begin
      Ensure_Parent (New_Path, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      if Hostkit.Fs.Create_Hard_Link (Existing_Path, New_Path) then
         Result := Tarlib.Errors.OK;
      else
         Result := (Code => Tarlib.Errors.Output_Failure);
      end if;
   exception
      when others =>
         Result := (Code => Tarlib.Errors.Output_Failure);
   end Create_Hard_Link;

   procedure Open_Read
     (Source : in out File_Input_Source;
      Path   : String;
      Result : out Tarlib.Errors.Status) is
   begin
      if Ada.Streams.Stream_IO.Is_Open (Source.File) then
         Result := (Code => Tarlib.Errors.Invalid_State);
         return;
      end if;

      Ada.Streams.Stream_IO.Open
        (Source.File, Ada.Streams.Stream_IO.In_File, Path);
      Result := Tarlib.Errors.OK;
   exception
      when others =>
         Result := (Code => Tarlib.Errors.Input_Failure);
   end Open_Read;

   procedure Close
     (Source : in out File_Input_Source;
      Result : out Tarlib.Errors.Status) is
   begin
      if Ada.Streams.Stream_IO.Is_Open (Source.File) then
         Ada.Streams.Stream_IO.Close (Source.File);
      end if;
      Result := Tarlib.Errors.OK;
   exception
      when others =>
         Result := (Code => Tarlib.Errors.Input_Failure);
   end Close;

   overriding procedure Read
     (Source : in out File_Input_Source;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Tarlib.Errors.Status) is
   begin
      Last := Data'First - 1;
      if not Ada.Streams.Stream_IO.Is_Open (Source.File) then
         Result := (Code => Tarlib.Errors.Invalid_State);
         return;
      elsif Ada.Streams.Stream_IO.End_Of_File (Source.File) then
         Result := Tarlib.Errors.OK;
         return;
      end if;

      Ada.Streams.Stream_IO.Read (Source.File, Data, Last);
      Result := Tarlib.Errors.OK;
   exception
      when others =>
         Last := Data'First - 1;
         Result := (Code => Tarlib.Errors.Input_Failure);
   end Read;

   procedure Create_Write
     (Sink   : in out File_Output_Sink;
      Path   : String;
      Result : out Tarlib.Errors.Status) is
   begin
      if Ada.Streams.Stream_IO.Is_Open (Sink.File) then
         Result := (Code => Tarlib.Errors.Invalid_State);
         return;
      end if;

      Ensure_Parent (Path, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Ada.Streams.Stream_IO.Create
        (Sink.File, Ada.Streams.Stream_IO.Out_File, Path);
      Result := Tarlib.Errors.OK;
   exception
      when others =>
         Result := (Code => Tarlib.Errors.Output_Failure);
   end Create_Write;

   procedure Close
     (Sink   : in out File_Output_Sink;
      Result : out Tarlib.Errors.Status) is
   begin
      if Ada.Streams.Stream_IO.Is_Open (Sink.File) then
         Ada.Streams.Stream_IO.Close (Sink.File);
      end if;
      Result := Tarlib.Errors.OK;
   exception
      when others =>
         Result := (Code => Tarlib.Errors.Output_Failure);
   end Close;

   overriding procedure Write
     (Sink   : in out File_Output_Sink;
      Data   : Ada.Streams.Stream_Element_Array;
      Result : out Tarlib.Errors.Status) is
   begin
      if not Ada.Streams.Stream_IO.Is_Open (Sink.File) then
         Result := (Code => Tarlib.Errors.Invalid_State);
         return;
      end if;

      Ada.Streams.Stream_IO.Write (Sink.File, Data);
      Result := Tarlib.Errors.OK;
   exception
      when others =>
         Result := (Code => Tarlib.Errors.Output_Failure);
   end Write;

   procedure Add_File
     (Archive         : in out Tarlib.Writers.Writer;
      Filesystem_Path : String;
      Archive_Path    : String;
      Result          : out Tarlib.Errors.Status)
   is
      Source : File_Input_Source;
      Size   : constant Tarlib.Byte_Count :=
        Tarlib.Byte_Count
          (Interfaces.Unsigned_64
             (Ada.Directories.Size (Filesystem_Path)));
      Buffer : Ada.Streams.Stream_Element_Array (1 .. 16#4000#);
      Last   : Ada.Streams.Stream_Element_Offset;
   begin
      Open_Read (Source, Filesystem_Path, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Tarlib.Writers.Begin_File (Archive, Archive_Path, Size, Result);
      if Result.Code /= Tarlib.Errors.Success then
         Close (Source, Result);
         return;
      end if;

      loop
         Read (Source, Buffer, Last, Result);
         if Result.Code /= Tarlib.Errors.Success then
            return;
         end if;

         exit when Last < Buffer'First;
         Tarlib.Writers.Write (Archive, Buffer (Buffer'First .. Last), Result);
         if Result.Code /= Tarlib.Errors.Success then
            return;
         end if;
      end loop;

      Close (Source, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Tarlib.Writers.End_Entry (Archive, Result);
   exception
      when others =>
         Result := (Code => Tarlib.Errors.Input_Failure);
   end Add_File;

   procedure Add_Tree
     (Archive         : in out Tarlib.Writers.Writer;
      Filesystem_Path : String;
      Archive_Path    : String;
      Result          : out Tarlib.Errors.Status)
   is
      Search : Ada.Directories.Search_Type;
      Search_Started : Boolean := False;
   begin
      case Ada.Directories.Kind (Filesystem_Path) is
         when Ada.Directories.Ordinary_File =>
            Add_File (Archive, Filesystem_Path, Archive_Path, Result);

         when Ada.Directories.Directory =>
            Tarlib.Writers.Add_Directory
              (Archive, Directory_Archive_Path (Archive_Path), Result);
            if Result.Code /= Tarlib.Errors.Success then
               return;
            end if;

            Ada.Directories.Start_Search
              (Search, Filesystem_Path, "*",
               [Ada.Directories.Ordinary_File => True,
                Ada.Directories.Directory => True,
                Ada.Directories.Special_File => True]);
            Search_Started := True;
            while Ada.Directories.More_Entries (Search) loop
               declare
                  Item : Ada.Directories.Directory_Entry_Type;
               begin
                  Ada.Directories.Get_Next_Entry (Search, Item);
                  declare
                     Name : constant String :=
                       Ada.Directories.Simple_Name (Item);
                  begin
                     if Name /= "." and then Name /= ".." then
                        Add_Tree
                          (Archive,
                           Ada.Directories.Full_Name (Item),
                           Directory_Archive_Path (Archive_Path) & Name,
                           Result);
                        if Result.Code /= Tarlib.Errors.Success then
                           Ada.Directories.End_Search (Search);
                           Search_Started := False;
                           return;
                        end if;
                     end if;
                  end;
               end;
            end loop;
            Ada.Directories.End_Search (Search);
            Search_Started := False;
            Result := Tarlib.Errors.OK;

         when Ada.Directories.Special_File =>
            Result := (Code => Tarlib.Errors.Invalid_Entry_Kind);
      end case;
   exception
      when others =>
         if Search_Started then
            Ada.Directories.End_Search (Search);
         end if;
         Result := (Code => Tarlib.Errors.Input_Failure);
   end Add_Tree;

   procedure Extract_All
     (Archive               : in out Tarlib.Readers.Reader;
      Destination_Directory : String;
      Result                : out Tarlib.Errors.Status)
   is
      Options : constant Extraction_Options :=
        (Unsupported_Entries => Reject_Unsupported,
         Apply_Permissions   => False,
         Apply_Timestamps    => False,
         Apply_Ownership     => False,
         Create_Special_Entries => False,
         Extract_GNU_Metadata => False,
         Device_Layout => Native_Device_Layout,
         Apply_Extended_Attributes => False,
         Apply_ACLs => False,
         Apply_File_Flags => False,
         Apply_Native_ACLs => False,
         Apply_Native_File_Flags => False);
   begin
      Extract_All (Archive, Destination_Directory, Options, Result);
   end Extract_All;

   procedure Extract_All
     (Archive               : in out Tarlib.Readers.Reader;
      Destination_Directory : String;
      Options               : Extraction_Options;
      Result                : out Tarlib.Errors.Status)
   is
      Info      : Tarlib.Readers.Entry_Info;
      Has_Entry : Boolean;
      Buffer    : Ada.Streams.Stream_Element_Array (1 .. 16#4000#);
      Last      : Ada.Streams.Stream_Element_Offset;
      Sink      : File_Output_Sink;
   begin
      Ada.Directories.Create_Path (Destination_Directory);

      loop
         Tarlib.Readers.Next_Entry (Archive, Info, Has_Entry, Result);
         if Result.Code /= Tarlib.Errors.Success or else not Has_Entry then
            return;
         end if;

         declare
            Target : constant String :=
              Join (Destination_Directory, Tarlib.Readers.Path (Info));
         begin
            case Tarlib.Readers.Kind (Info) is
               when Tarlib.Entries.Directory =>
                  Ada.Directories.Create_Path (Target);
                  Apply_Metadata
                    (Target, Tarlib.Readers.Metadata (Info), Options, Result);
                  if Result.Code /= Tarlib.Errors.Success then
                     return;
                  end if;
                  Apply_Vendor_Metadata (Target, Info, Options, Result);
                  if Result.Code /= Tarlib.Errors.Success then
                     return;
                  end if;

               when Tarlib.Entries.Regular_File
                  | Tarlib.Entries.Multi_Volume =>
                  if Tarlib.Readers.Kind (Info) = Tarlib.Entries.Multi_Volume
                    and then not Options.Extract_GNU_Metadata
                  then
                     if Options.Unsupported_Entries = Skip_Unsupported then
                        Tarlib.Readers.Skip_Entry (Archive, Result);
                        if Result.Code = Tarlib.Errors.Success then
                           goto Continue_Archive;
                        end if;
                     else
                        Result := (Code => Tarlib.Errors.Invalid_Entry_Kind);
                     end if;
                     return;
                  end if;

                  Ensure_Parent (Target, Result);
                  if Result.Code /= Tarlib.Errors.Success then
                     return;
                  end if;

                  Create_Write (Sink, Target, Result);
                  if Result.Code /= Tarlib.Errors.Success then
                     return;
                  end if;

                  loop
                     Tarlib.Readers.Read (Archive, Buffer, Last, Result);
                     if Result.Code /= Tarlib.Errors.Success then
                        return;
                     end if;

                     exit when Last < Buffer'First;
                     Write (Sink, Buffer (Buffer'First .. Last), Result);
                     if Result.Code /= Tarlib.Errors.Success then
                        return;
                     end if;
                  end loop;

                  Close (Sink, Result);
                  if Result.Code /= Tarlib.Errors.Success then
                     return;
                  end if;

                  Apply_Metadata
                    (Target, Tarlib.Readers.Metadata (Info), Options, Result);
                  if Result.Code /= Tarlib.Errors.Success then
                     return;
                  end if;
                  Apply_Vendor_Metadata (Target, Info, Options, Result);
                  if Result.Code /= Tarlib.Errors.Success then
                     return;
                  end if;

               when Tarlib.Entries.Incremental_Dump =>
                  if not Options.Extract_GNU_Metadata then
                     if Options.Unsupported_Entries = Skip_Unsupported then
                        Tarlib.Readers.Skip_Entry (Archive, Result);
                        if Result.Code = Tarlib.Errors.Success then
                           goto Continue_Archive;
                        end if;
                     else
                        Result := (Code => Tarlib.Errors.Invalid_Entry_Kind);
                     end if;
                     return;
                  end if;

                  declare
                     Listing : Tarlib.Readers.Incremental_Listing;
                  begin
                     Ada.Directories.Create_Path (Target);
                     Tarlib.Readers.Read_Incremental_Dump
                       (Archive, Listing, Result);
                     if Result.Code /= Tarlib.Errors.Success then
                        return;
                     end if;

                     Write_Incremental_Listing (Target, Listing, Result);
                     if Result.Code /= Tarlib.Errors.Success then
                        return;
                     end if;

                     Apply_Metadata
                       (Target, Tarlib.Readers.Metadata (Info), Options,
                        Result);
                     if Result.Code /= Tarlib.Errors.Success then
                        return;
                     end if;
                     Apply_Vendor_Metadata (Target, Info, Options, Result);
                     if Result.Code /= Tarlib.Errors.Success then
                        return;
                     end if;
                  end;

               when Tarlib.Entries.Volume_Label =>
                  if not Options.Extract_GNU_Metadata then
                     if Options.Unsupported_Entries = Skip_Unsupported then
                        Tarlib.Readers.Skip_Entry (Archive, Result);
                        if Result.Code = Tarlib.Errors.Success then
                           goto Continue_Archive;
                        end if;
                     else
                        Result := (Code => Tarlib.Errors.Invalid_Entry_Kind);
                     end if;
                     return;
                  end if;

                  Create_Write
                    (Sink, Join (Destination_Directory, ".tar-volume-label"),
                     Result);
                  if Result.Code /= Tarlib.Errors.Success then
                     return;
                  end if;
                  Write_Text
                    (Sink, Tarlib.Readers.Path (Info) & Character'Val (10),
                     Result);
                  if Result.Code /= Tarlib.Errors.Success then
                     return;
                  end if;
                  Close (Sink, Result);
                  if Result.Code /= Tarlib.Errors.Success then
                     return;
                  end if;

               when Tarlib.Entries.Symbolic_Link =>
                  Create_Symbolic_Link
                    (Tarlib.Readers.Link_Path (Info), Target, Result);
                  if Result.Code /= Tarlib.Errors.Success then
                     return;
                  end if;

               when Tarlib.Entries.Hard_Link =>
                  Create_Hard_Link
                    (Join
                       (Destination_Directory,
                        Tarlib.Readers.Link_Path (Info)),
                     Target, Result);
                  if Result.Code /= Tarlib.Errors.Success then
                     return;
                  end if;

               when Tarlib.Entries.FIFO =>
                  Create_FIFO
                    (Target, Tarlib.Readers.Metadata (Info), Options, Result);
                  if Result.Code /= Tarlib.Errors.Success then
                     if Options.Unsupported_Entries = Skip_Unsupported
                       and then Result.Code = Tarlib.Errors.Invalid_Entry_Kind
                     then
                        Tarlib.Readers.Skip_Entry (Archive, Result);
                        if Result.Code = Tarlib.Errors.Success then
                           goto Continue_Archive;
                        end if;
                     end if;
                     return;
                  end if;

               when Tarlib.Entries.Character_Device
                  | Tarlib.Entries.Block_Device =>
                  Create_Device
                    (Target, Tarlib.Readers.Kind (Info),
                     Tarlib.Readers.Device (Info),
                     Tarlib.Readers.Metadata (Info), Options, Result);
                  if Result.Code /= Tarlib.Errors.Success then
                     if Options.Unsupported_Entries = Skip_Unsupported
                       and then Result.Code = Tarlib.Errors.Invalid_Entry_Kind
                     then
                        Tarlib.Readers.Skip_Entry (Archive, Result);
                        if Result.Code = Tarlib.Errors.Success then
                           goto Continue_Archive;
                        end if;
                     end if;
                     return;
                  end if;

               when others =>
                  if Options.Unsupported_Entries = Skip_Unsupported then
                     Tarlib.Readers.Skip_Entry (Archive, Result);
                     if Result.Code /= Tarlib.Errors.Success then
                        return;
                     end if;
                  else
                     Result := (Code => Tarlib.Errors.Invalid_Entry_Kind);
                     return;
                  end if;
            end case;
         end;

         <<Continue_Archive>>
         null;
      end loop;
   exception
      when others =>
         Result := (Code => Tarlib.Errors.Output_Failure);
   end Extract_All;

   procedure Reassemble_Multi_Volume_File
     (Volume_Path_List : String;
      Output_Path      : String;
      Result           : out Tarlib.Errors.Status)
   is
      Output : Ada.Streams.Stream_IO.File_Type;
      Output_Open : Boolean := False;
      Expected_Offset : Tarlib.Byte_Count := 0;
      Buffer : Ada.Streams.Stream_Element_Array (1 .. 16#4000#);
      Last   : Ada.Streams.Stream_Element_Offset;

      procedure Process_Volume (Path : String) is
         Source : File_Input_Source;
         Reader : Tarlib.Readers.Reader;
         Info : Tarlib.Readers.Entry_Info;
         Has_Entry : Boolean;
         Source_Open : Boolean := False;
      begin
         if Path'Length = 0 then
            Result := Tarlib.Errors.OK;
            return;
         end if;

         Open_Read (Source, Path, Result);
         if Result.Code /= Tarlib.Errors.Success then
            return;
         end if;
         Source_Open := True;

         Tarlib.Readers.Initialize (Reader, Source, Result);
         if Result.Code /= Tarlib.Errors.Success then
            Close (Source, Result);
            return;
         end if;

         Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Result);
         if Result.Code /= Tarlib.Errors.Success then
            Close (Source, Result);
            return;
         elsif not Has_Entry then
            Result := (Code => Tarlib.Errors.Invalid_Archive);
            Close (Source, Result);
            return;
         elsif Tarlib.Readers.Kind (Info) = Tarlib.Entries.Regular_File then
            if Expected_Offset /= 0 then
               Result := (Code => Tarlib.Errors.Invalid_Entry_Kind);
               Close (Source, Result);
               return;
            end if;
         elsif Tarlib.Readers.Kind (Info) = Tarlib.Entries.Multi_Volume then
            if Tarlib.Readers.Multi_Volume_Offset (Info) /= Expected_Offset then
               Result := (Code => Tarlib.Errors.Invalid_Metadata);
               Close (Source, Result);
               return;
            end if;
         else
            Result := (Code => Tarlib.Errors.Invalid_Entry_Kind);
            Close (Source, Result);
            return;
         end if;

         loop
            Tarlib.Readers.Read (Reader, Buffer, Last, Result);
            if Result.Code /= Tarlib.Errors.Success then
               Close (Source, Result);
               return;
            end if;

            exit when Last < Buffer'First;
            Ada.Streams.Stream_IO.Write
              (Output, Buffer (Buffer'First .. Last));
            Expected_Offset :=
              Expected_Offset
              + Tarlib.Byte_Count (Last - Buffer'First + 1);
         end loop;

         Close (Source, Result);
         Source_Open := False;
      exception
         when others =>
            if Source_Open then
               Close (Source, Result);
            end if;
            Result := (Code => Tarlib.Errors.Output_Failure);
      end Process_Volume;

      Start : Natural := Volume_Path_List'First;
   begin
      Ensure_Parent (Output_Path, Result);
      if Result.Code /= Tarlib.Errors.Success then
         return;
      end if;

      Ada.Streams.Stream_IO.Create
        (Output, Ada.Streams.Stream_IO.Out_File, Output_Path);
      Output_Open := True;

      for Index in Volume_Path_List'Range loop
         if Volume_Path_List (Index) = Character'Val (10) then
            Process_Volume (Volume_Path_List (Start .. Index - 1));
            if Result.Code /= Tarlib.Errors.Success then
               Ada.Streams.Stream_IO.Close (Output);
               return;
            end if;
            Start := Index + 1;
         end if;
      end loop;

      if Start <= Volume_Path_List'Last then
         Process_Volume (Volume_Path_List (Start .. Volume_Path_List'Last));
         if Result.Code /= Tarlib.Errors.Success then
            Ada.Streams.Stream_IO.Close (Output);
            return;
         end if;
      end if;

      Ada.Streams.Stream_IO.Close (Output);
      Output_Open := False;
      Result := Tarlib.Errors.OK;
   exception
      when others =>
         if Output_Open then
            Ada.Streams.Stream_IO.Close (Output);
         end if;
         Result := (Code => Tarlib.Errors.Output_Failure);
   end Reassemble_Multi_Volume_File;
end Tarlib.Files;
